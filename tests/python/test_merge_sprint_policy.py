#!/usr/bin/env python3
"""Tests de scripts/merge-sprint-policy.py (SE-512 S1: AC-12b, AC-12c con activación única, AC-8 en el recibo).

Reutiliza el fixture de SE-488 (tests/python/test_approval_receipt.py): repo de
aprobaciones local con génesis propio y merges firmados con una clave GPG de prueba
que hace de web-flow. `gh` es un script falso que devuelve la PR asociada al merge.
"""
import copy
import datetime as dt
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "merge-sprint-policy.py")


def _cargar(nombre, ruta):
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mp = _cargar("merge_sprint_policy", SCRIPT)
fx = _cargar("fixture_se488", os.path.join(ROOT, "tests", "python", "test_approval_receipt.py"))

H = dt.timedelta(hours=1)
MIN = dt.timedelta(minutes=1)
NB = dt.datetime(2026, 11, 10, 22, 0, 0, tzinfo=dt.timezone.utc)   # not_before: 22:00
NA = NB + 10 * H                                                     # not_after: 08:00
fmt = mp.ar.fmt_fecha


def politica(**cambios):
    p = {"kind": "policy", "id": "0123456789abcdef", "not_before": fmt(NB), "not_after": fmt(NA),
         "repos": [{"repo": "org/savia", "base": "main", "include": ["docs/**"], "exclude": [],
                    "required_checks": ["CI"]}],
         "tiers": [1, 2], "max_merges": 12, "max_parks_in_row": 3, "universe": "open", "frozen_prs": [],
         "reviewers": ["revisora-a", "revisora-b"], "max_reviews_per_pr": 4,
         "runner_blob": "1" * 40, "classifier_blob": "2" * 40, "f5_blob": "3" * 40,
         "resolver_blob": "4" * 40, "main_pending_timeout": 20}
    p.update(cambios)
    return p


class Base(fx.Base):
    def setUp(self):
        super().setUp()
        self.cfg = {**self.pol, "tipos": ["savia-merge", "savia-politica"], "espejo": self.repo,
                    "repo_aprobaciones": "org/aprobaciones"}
        self.pulls = os.path.join(self.tmp, "pulls.json")
        gh = os.path.join(self.tmp, "gh")
        with open(gh, "w") as f:
            f.write('#!/usr/bin/env bash\ncase "$*" in\n  api*/commits/*/pulls*) cat "$FAKE_PULLS" ;;\n'
                    '  *) exit 1 ;;\nesac\n')
        os.chmod(gh, 0o755)
        self._env = {k: os.environ.get(k) for k in ("GH", "FAKE_PULLS")}
        os.environ.update(GH=gh, FAKE_PULLS=self.pulls)
        self.pol_obj = politica()

    def tearDown(self):
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        super().tearDown()

    # -------------------------------------------------------------- aprobación
    def peticion(self, pol=None, emitida=NB - 30 * MIN, art=None, ruta=None, cfg=None):
        pol = pol or self.pol_obj
        if art is None:
            ruta, art = mp.nuevo_artefacto(pol, emitida)
        return {"ruta": ruta, "artefacto": art, "digest": mp.digest(pol),
                "aprobacion_cfg": mp.huella_config(cfg or self.cfg),
                "titulo": mp.generar_titulo(pol), "cuerpo": mp.generar_cuerpo(pol, mp.generar_resumen(pol))}

    def aprobar_pet(self, pet, merge=NB - 20 * MIN, commit_fecha=None, extra=None, titulo=None,
                    cuerpo=None, **kw):
        """Rama de la App con el artefacto (commit con fecha `emitida`) + merge firmado + PR falsa."""
        self.n += 1
        rama = f"politica{self.n}"
        fecha = commit_fecha or mp.ar.parse_fecha(pet["artefacto"]["emitida"])
        self.git("checkout", "-q", "-b", rama, "main")
        self.escribir(pet["ruta"], json.dumps(pet["artefacto"], indent=2, sort_keys=True))
        if extra:
            self.escribir(extra, "otro\n")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", pet["titulo"], fecha=fecha)
        self.git("checkout", "-q", "main")
        m = self.fusionar([rama], fecha=merge, **kw)
        with open(self.pulls, "w") as f:
            json.dump([{"title": pet["titulo"] if titulo is None else titulo,
                        "body": pet["cuerpo"] if cuerpo is None else cuerpo, "merge_commit_sha": m}], f)
        return m

    def v(self, pet, ahora=NB + H, pol=None, cfg=None):
        return mp.verificar(pol or self.pol_obj, cfg or self.cfg, pet, ahora)

    def assertCodigo(self, r, codigo):
        self.assertEqual(r["codigo"], codigo, r)


class AC12bRecibo(Base):
    def test_positivo_recibo_valido_da_grant(self):
        pet = self.peticion()
        m = self.aprobar_pet(pet)
        r = self.v(pet)
        self.assertCodigo(r, mp.GRANT)
        self.assertEqual(r["commit"], m)
        self.assertEqual(r["digest"], mp.digest(self.pol_obj))
        self.assertEqual(r["unidad"], "politica@" + mp.digest(self.pol_obj))
        self.assertEqual(r["ventana_efectiva"], [fmt(NB), fmt(NA)])

    def assertSinGrant(self, r, condicion, motivo):
        """Código 3 por el motivo esperado, no por una excepción cualquiera (cajón de sastre)."""
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertEqual(r.get("condicion"), condicion, r)
        self.assertIn(motivo, r.get("motivo", ""), r)

    def test_sin_merge_no_hay_grant_aunque_exista_el_fichero(self):
        self.assertSinGrant(self.v(self.peticion()), "SE-512", "sin PR de aprobación fusionada")

    def test_sin_firma_de_webflow(self):
        pet = self.peticion()
        self.aprobar_pet(pet, firma=None)
        self.assertSinGrant(self.v(pet), "R2.3", "sin firma válida")

    def test_firma_de_otra_clave(self):
        pet = self.peticion()
        self.aprobar_pet(pet, firma="otra")
        self.assertSinGrant(self.v(pet), "R2.3", "sin firma válida")

    def test_autor_bot(self):
        pet = self.peticion()
        self.aprobar_pet(pet, autor=fx.BOT)
        self.assertSinGrant(self.v(pet), "R2.4", "autora")

    def test_pr_con_dos_ficheros(self):
        pet = self.peticion()
        self.aprobar_pet(pet, extra="aprobaciones/otro.txt")
        self.assertSinGrant(self.v(pet), "R2.5", "exactamente un fichero")

    def test_otra_peticion_fusionada_de_la_misma_politica_no_vale_por_la_registrada(self):
        """El merge que cuenta es el del artefacto de la petición registrada, no otro del mismo id."""
        pet = self.peticion()
        otra = self.peticion()
        self.assertNotEqual(otra["ruta"], pet["ruta"])
        self.aprobar_pet(otra)
        self.assertSinGrant(self.v(pet), "SE-512", "sin PR de aprobación fusionada")
        self.assertCodigo(self.v(otra), mp.GRANT)

    def test_ruta_de_la_peticion_de_otra_politica(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        ajena = {**pet, "ruta": pet["ruta"].replace("0123456789abcdef", "fedcba9876543210")}
        self.assertSinGrant(self.v(ajena), "SE-512", "no es de esta política")

    def test_tipo_no_habilitado_en_la_configuracion(self):
        cfg = {**self.cfg, "tipos": ["savia-merge"]}
        pet = self.peticion(cfg=cfg)
        self.aprobar_pet(pet)
        r = self.v(pet, cfg=cfg)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertEqual(r["condicion"], "R2.9")

    def test_objeto_distinto_del_fichero_de_politica_es_anomalia(self):
        """AC-8: el fichero local editado tras aprobar no coincide con el digest de la petición."""
        pet = self.peticion()
        self.aprobar_pet(pet)
        for campo, valor in (("max_merges", 20), ("not_after", fmt(NA + H)), ("tiers", [1]),
                             ("reviewers", ["revisora-a", "revisora-c"])):
            with self.subTest(campo):
                editada = politica(**{campo: valor})
                r = self.v(pet, pol=editada)
                self.assertCodigo(r, mp.ANOMALIA)
                self.assertEqual(r["condicion"], "digest")
        editada = politica()
        editada["repos"][0]["include"].append("scripts/**")
        self.assertCodigo(self.v(pet, pol=editada), mp.ANOMALIA)

    def test_objeto_distinto_aunque_la_peticion_local_tambien_se_edite(self):
        """Editar la política y su registro de petición a la vez: lo que manda es el objeto firmado."""
        pet = self.peticion()
        self.aprobar_pet(pet)
        editada = politica(max_merges=40)
        pet2 = {**pet, "digest": mp.digest(editada)}
        r = self.v(pet2, pol=editada)
        self.assertCodigo(r, mp.ANOMALIA)

    def test_merge_antes_de_emitida(self):
        pet = self.peticion(emitida=NB - 30 * MIN)
        self.aprobar_pet(pet, merge=NB - 40 * MIN)
        self.assertSinGrant(self.v(pet), "R2.7", "fecha del merge")

    def test_merge_posterior_a_not_after(self):
        pet = self.peticion()
        self.aprobar_pet(pet, merge=NA + MIN)
        self.assertSinGrant(self.v(pet, ahora=NA + 2 * MIN), "R2.7", "fecha del merge")
        # Dentro de la ventana pero antes del merge (08:01): el suelo monótono ya lo impide.
        self.assertSinGrant(self.v(pet, ahora=NB + H), "R2.7", "suelo monótono")

    def _artefacto_a_mano(self, **cambios):
        ruta, art = mp.nuevo_artefacto(self.pol_obj, NB - 30 * MIN)
        return ruta, {**art, **cambios}

    def test_caduca_distinto_de_not_after(self):
        ruta, art = self._artefacto_a_mano(caduca=fmt(NA + H))
        pet = self.peticion(art=art, ruta=ruta)
        self.aprobar_pet(pet)
        r = self.v(pet)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertEqual(r["condicion"], "SE-512")
        with self.assertRaises(mp.ar.Rechazo):
            mp.ar.validar_artefacto(art, ruta)

    def test_emitida_anterior_a_not_before_menos_1h(self):
        ruta, art = self._artefacto_a_mano(emitida=fmt(NB - H - MIN))
        pet = self.peticion(art=art, ruta=ruta)
        self.aprobar_pet(pet, merge=NB - 50 * MIN)
        r = self.v(pet)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertIn("not_before", r["motivo"])
        # Caso límite: emitida == not_before − 1 h sí vale.
        mp.ar.validar_artefacto({**art, "emitida": fmt(NB - H)}, ruta)

    def test_emitida_distinta_de_la_fecha_del_commit_del_artefacto(self):
        pet = self.peticion()
        self.aprobar_pet(pet, commit_fecha=NB - 25 * MIN)
        r = self.v(pet)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertIn("emitida distinta", r["motivo"])

    def test_nonce_anotado_para_otro_digest_es_libro_manipulado(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        os.makedirs(self.cfg["libro"], exist_ok=True)
        with open(os.path.join(self.cfg["libro"], "consumidos.jsonl"), "w") as f:
            f.write(json.dumps({"nonce": pet["artefacto"]["nonce"], "unidad": "politica@" + "f" * 64}) + "\n")
        self.assertCodigo(self.v(pet), mp.MANIPULADO)

    def _pr_alterada(self, campo, valor):
        pet = self.peticion()
        self.assertNotEqual(valor, pet[campo])
        self.aprobar_pet(pet, **{campo: valor})
        r = self.v(pet)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertEqual(r["condicion"], "SE-512")
        self.assertIn("título o descripción", r["motivo"])

    def test_titulo_distinto_del_generado(self):
        pet = self.peticion()
        self._pr_alterada("titulo", pet["titulo"].replace("máximo 12", "máximo 40"))

    def test_descripcion_distinta_de_la_generada(self):
        pet = self.peticion()
        self._pr_alterada("cuerpo", pet["cuerpo"].replace("12 fusiones", "40 fusiones"))

    def test_descripcion_con_una_linea_de_mas(self):
        pet = self.peticion()
        self._pr_alterada("cuerpo", pet["cuerpo"] + "Y también scripts/**.\n")

    def test_cuerpo_null_no_da_grant(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        with open(self.pulls) as f:
            pr = json.load(f)
        pr[0]["body"] = None
        with open(self.pulls, "w") as f:
            json.dump(pr, f)
        r = self.v(pet)
        self.assertCodigo(r, mp.SIN_GRANT)
        self.assertIn("título o descripción", r["motivo"])

    def test_normalizacion_documentada_crlf_y_blancos_finales_da_grant(self):
        """GitHub puede devolver CRLF o recortar el salto final: solo eso se normaliza."""
        pet = self.peticion()
        self.aprobar_pet(pet, titulo=pet["titulo"] + " ",
                         cuerpo=pet["cuerpo"].rstrip("\n").replace("\n", "\r\n") + "  \r\n")
        self.assertCodigo(self.v(pet), mp.GRANT)

    def test_pr_ilegible_en_github_no_da_grant(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        os.remove(self.pulls)
        self.assertCodigo(self.v(pet), mp.SIN_GRANT)

    def test_espejo_sin_sincronizar(self):
        espejo = os.path.join(self.tmp, "espejo")
        self.git("clone", "-q", self.repo, espejo)       # copia de antes del merge
        pet = self.peticion()
        self.aprobar_pet(pet)
        self.assertCodigo(self.v(pet, cfg={**self.cfg, "espejo": espejo}), mp.SIN_GRANT)
        self.assertCodigo(self.v(pet), mp.GRANT)

    def test_configuracion_de_aprobacion_cambiada_es_anomalia(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        vacio = os.path.join(self.tmp, "libro-vacio")
        for cambio in ({"autor": {"email": "otra@fixture.invalid"}}, {"genesis": "9" * 40},
                       {"huella_webflow": self.fpr_otra},
                       # Un libro vacío «resetearía» el uso único; otro repo cambiaría de dónde se
                       # leen el título y el cuerpo de la PR.
                       {"libro": vacio}, {"repo_aprobaciones": "org/otro"},
                       {"tipos": ["savia-politica"]}):
            with self.subTest(cambio):
                r = self.v(pet, cfg={**self.cfg, **cambio})
                self.assertCodigo(r, mp.ANOMALIA)
                self.assertEqual(r["condicion"], "configuracion")

    def test_sin_registro_de_peticion(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        self.assertCodigo(self.v(None), mp.SIN_GRANT)

    def test_verificar_no_consume_ni_aprueba(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        self.assertCodigo(self.v(pet), mp.GRANT)
        self.assertCodigo(self.v(pet), mp.GRANT)
        self.assertFalse(os.path.exists(os.path.join(self.cfg["libro"], "consumidos.jsonl")))

    def test_activacion_anotada_del_mismo_digest_no_es_reuso(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        os.makedirs(self.cfg["libro"], exist_ok=True)
        with open(os.path.join(self.cfg["libro"], "consumidos.jsonl"), "w") as f:
            f.write(json.dumps({"nonce": pet["artefacto"]["nonce"],
                                "unidad": "politica@" + mp.digest(self.pol_obj)}) + "\n")
        r = self.v(pet)
        self.assertCodigo(r, mp.GRANT)
        self.assertTrue(r["activada"])


class AC12cVigencia(Base):
    """not_before a las 22:00, not_after a las 08:00."""

    def test_pr_aun_sin_fusionar_a_las_2230_es_sin_grant_no_7(self):
        pet = self.peticion()
        self.assertCodigo(self.v(pet, ahora=NB + 30 * MIN), mp.SIN_GRANT)

    def test_merge_a_las_2130_da_7_hasta_las_22_y_grant_desde_las_22(self):
        pet = self.peticion(emitida=NB - 40 * MIN)
        self.aprobar_pet(pet, merge=NB - 30 * MIN)
        r = self.v(pet, ahora=NB - 15 * MIN)
        self.assertCodigo(r, mp.ANTES)
        self.assertEqual(r["veredicto"], "ANTES_DE_VENTANA")
        self.assertCodigo(self.v(pet, ahora=NB - mp.dt.timedelta(seconds=1)), mp.ANTES)
        self.assertCodigo(self.v(pet, ahora=NB), mp.GRANT)

    def test_merge_a_las_2330_grant_desde_las_2330_y_antes_sin_grant(self):
        pet = self.peticion(emitida=NB + 60 * MIN)
        self.aprobar_pet(pet, merge=NB + 90 * MIN)
        r = self.v(pet, ahora=NB + 90 * MIN)
        self.assertCodigo(r, mp.GRANT)
        self.assertEqual(r["ventana_efectiva"], [fmt(NB + 90 * MIN), fmt(NA)])
        self.assertCodigo(self.v(pet, ahora=NB + 60 * MIN), mp.SIN_GRANT)

    def test_merge_despues_de_not_after_sin_grant(self):
        pet = self.peticion(emitida=NB + 9 * H)
        self.aprobar_pet(pet, merge=NA + MIN)
        self.assertCodigo(self.v(pet, ahora=NA + 5 * MIN), mp.SIN_GRANT)

    def test_now_igual_a_not_after_sin_grant(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        self.assertCodigo(self.v(pet, ahora=NA - mp.dt.timedelta(seconds=1)), mp.GRANT)
        self.assertCodigo(self.v(pet, ahora=NA), mp.SIN_GRANT)


class AC12cActivacion(Base):
    """La activación (S2 la llama desde `run --policy`) se anota una sola vez."""

    def _lineas(self):
        try:
            with open(os.path.join(self.cfg["libro"], "consumidos.jsonl")) as f:
                return [json.loads(l) for l in f if l.strip()]
        except FileNotFoundError:
            return []

    def test_dos_pasadas_anotan_una_sola_activacion(self):
        pet = self.peticion()
        self.aprobar_pet(pet)
        r1 = mp.activar(self.pol_obj, self.cfg, pet, NB + H)
        r2 = mp.activar(self.pol_obj, self.cfg, pet, NB + 2 * H)
        self.assertCodigo(r1, mp.GRANT)
        self.assertCodigo(r2, mp.GRANT)
        lineas = self._lineas()
        self.assertEqual(len(lineas), 1, lineas)
        self.assertEqual(lineas[0]["unidad"], "politica@" + mp.digest(self.pol_obj))
        self.assertEqual(lineas[0]["estado"], "activada")

    def test_procesos_concurrentes_anotan_una_sola_activacion(self):
        import multiprocessing
        pet = self.peticion()
        self.aprobar_pet(pet)
        ctx = multiprocessing.get_context("fork")
        cola = ctx.Queue()

        def hijo():
            cola.put(mp.activar(self.pol_obj, self.cfg, pet, NB + H)["codigo"])
        procs = [ctx.Process(target=hijo) for _ in range(4)]
        for p in procs:
            p.start()
        for p in procs:
            p.join(60)
        self.assertEqual(sorted(cola.get(timeout=5) for _ in procs), [mp.GRANT] * 4)
        self.assertEqual(len(self._lineas()), 1, self._lineas())

    def test_sin_recibo_no_activa(self):
        pet = self.peticion()
        self.assertCodigo(mp.activar(self.pol_obj, self.cfg, pet, NB + H), mp.SIN_GRANT)
        self.assertEqual(self._lineas(), [])

    def test_antes_de_la_ventana_no_activa(self):
        pet = self.peticion(emitida=NB - 40 * MIN)
        self.aprobar_pet(pet, merge=NB - 30 * MIN)
        self.assertCodigo(mp.activar(self.pol_obj, self.cfg, pet, NB - 10 * MIN), mp.ANTES)
        self.assertEqual(self._lineas(), [])


class VentanaPorDefectoDST(unittest.TestCase):
    """Las 08:00 son locales también la noche del cambio de hora (Europe/Madrid, 2026-10-25)."""

    def setUp(self):
        import time
        self._tz = os.environ.get("TZ")
        os.environ["TZ"] = "Europe/Madrid"
        time.tzset()

    def tearDown(self):
        import time
        if self._tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = self._tz
        time.tzset()

    def test_noche_del_cambio_de_hora_acaba_a_las_08_locales(self):
        nb = dt.datetime(2026, 10, 24, 20, 0, 0, tzinfo=dt.timezone.utc)   # 22:00 CEST
        self.assertEqual(fmt(mp.fin_por_defecto(nb)), "2026-10-25T07:00:00Z")  # 08:00 CET

    def test_emitida_de_madrugada_acaba_a_las_08_del_mismo_dia(self):
        nb = dt.datetime(2026, 11, 10, 1, 0, 0, tzinfo=dt.timezone.utc)    # 02:00 CET
        self.assertEqual(fmt(mp.fin_por_defecto(nb)), "2026-11-10T07:00:00Z")


class Peticion(Base):
    def test_artefacto_de_la_peticion_valida_y_caduca_es_not_after(self):
        ruta, art = mp.nuevo_artefacto(self.pol_obj, NB - 30 * MIN)
        self.assertRegex(ruta, r"^aprobaciones/savia-politica/20261110-0123456789abcdef-[0-9a-f]{8}\.json$")
        self.assertEqual(art["caduca"], fmt(NA))
        self.assertEqual(art["resumen"], mp.generar_resumen(self.pol_obj))
        self.assertEqual(mp.ar.validar_artefacto(art, ruta), (NB - 30 * MIN, NA))

    def test_peticion_fuera_de_plazo_rechazada(self):
        with self.assertRaises(mp.Rechazada):
            mp.nuevo_artefacto(self.pol_obj, NB - H - MIN)
        with self.assertRaises(mp.Rechazada):
            mp.nuevo_artefacto(self.pol_obj, NA)

    def test_resumen_alterado_rechazado(self):
        ruta, art = mp.nuevo_artefacto(self.pol_obj, NB - 30 * MIN)
        with self.assertRaises(mp.ar.Rechazo):
            mp.ar.validar_artefacto({**art, "resumen": art["resumen"].replace("12 fusiones", "40 fusiones")}, ruta)

    def test_politica_invalida_rechazada_en_el_verificador(self):
        for cambio in ({"tiers": [3]}, {"max_merges": 41}, {"not_after": fmt(NB + 12 * H + MIN)},
                       {"reviewers": ["revisora-a", "savia-orchestrator"]}):
            with self.subTest(cambio), self.assertRaises(mp.ar.Rechazo):
                mp.ar.validar_objeto("savia-politica", politica(**cambio))

    def test_paridad_de_los_tipos_de_se488_en_la_copia(self):
        obj = {"repo": "o/r", "prs": [{"numero": 1, "head_sha": "a" * 40}]}
        self.assertEqual(mp.ar.generar_resumen("savia-merge", obj), fx.ar.generar_resumen("savia-merge", obj))

    def test_abrir_pr_commitea_con_fecha_emitida_y_abre_la_pr(self):
        remoto = os.path.join(self.tmp, "remoto.git")
        subprocess.run(["git", "clone", "-q", "--bare", self.repo, remoto], check=True)
        clon = os.path.join(self.tmp, "clon")
        subprocess.run(["git", "clone", "-q", remoto, clon], check=True)
        for k, val in (("user.name", "App"), ("user.email", "app@fixture.invalid")):
            subprocess.run(["git", "-C", clon, "config", k, val], check=True)
        log = os.path.join(self.tmp, "gh.log")
        gh = os.path.join(self.tmp, "gh-pr")
        with open(gh, "w") as f:
            f.write(f'#!/usr/bin/env bash\necho "$*" >> {log}\n')
        os.chmod(gh, 0o755)
        os.environ["GH"] = gh
        pet = self.peticion()
        mp.abrir_pr(pet, clon, "org/aprobaciones")
        rama = "politica-" + os.path.basename(pet["ruta"])[:-5]
        ct = subprocess.run(["git", "-C", remoto, "log", "-1", "--format=%ct", rama], check=True,
                            capture_output=True, text=True).stdout.strip()
        self.assertEqual(fmt(dt.datetime.fromtimestamp(int(ct), dt.timezone.utc)), pet["artefacto"]["emitida"])
        with open(log) as f:
            llamada = f.read()
        self.assertIn("pr create -R org/aprobaciones --base main --head " + rama, llamada)
        # Una segunda apertura con la misma rama no la pisa: falla.
        with self.assertRaises(subprocess.CalledProcessError):
            mp.abrir_pr(pet, clon, "org/aprobaciones")


class RequestCLI(unittest.TestCase):
    """policy-request: validaciones antes de cualquier efecto y una sola petición por política."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        self.fp, self.fc = os.path.join(self.tmp, "p.json"), os.path.join(self.tmp, "c.json")
        with open(self.fp, "w") as f:
            f.write(mp.canonico(politica()))
        self.clave = os.path.join(self.tmp, "clave.asc")
        with open(self.clave, "w") as f:
            f.write("clave de prueba\n")
        self.cfg_ok = {"genesis": "a" * 40, "autor": {"email": "op@fixture.invalid"}, "clave_webflow": self.clave,
                       "huella_webflow": "B" * 40, "tipos": ["savia-politica"], "libro": os.path.join(self.tmp, "libro"),
                       "espejo": os.path.join(self.tmp, "espejo"), "repo_aprobaciones": "org/aprobaciones"}
        self.cfg(self.cfg_ok)
        self.preq = os.path.join(self.home, "policy", "0123456789abcdef.request.json")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def cfg(self, c):
        with open(self.fc, "w") as f:
            json.dump(c, f)

    def req(self, *extra):
        return subprocess.run([sys.executable, SCRIPT, "--home", self.home, "request", "--politica", self.fp,
                               "--aprobacion", self.fc, "--ahora", fmt(NB - 30 * MIN), *extra],
                              capture_output=True, text=True)

    def test_segunda_peticion_de_la_misma_politica_rechazada_sin_pisar_la_primera(self):
        p = self.req()
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(self.preq) as f:
            primera = f.read()
        p = self.req()
        self.assertEqual(p.returncode, 2, p.stdout)
        self.assertIn("ya hay una petición", p.stderr)
        with open(self.preq) as f:
            self.assertEqual(f.read(), primera)

    def test_abrir_sin_clon_rechazada_sin_escribir_la_peticion(self):
        p = self.req("--abrir")
        self.assertEqual(p.returncode, 2)
        self.assertIn("--abrir exige --clon", p.stderr)
        self.assertFalse(os.path.exists(self.preq))

    def test_abrir_que_falla_da_2_sin_traceback_ni_peticion(self):
        p = self.req("--abrir", "--clon", os.path.join(self.tmp, "no-existe"))
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("no se pudo abrir la PR", p.stderr)
        self.assertNotIn("Traceback", p.stderr)
        self.assertFalse(os.path.exists(self.preq))

    def test_configuracion_incompleta_no_registra_peticion(self):
        """Una configuración que verify nunca podría verificar no bloquea la política."""
        for mala in ({}, {**self.cfg_ok, "tipos": ["savia-merge"]}, {**self.cfg_ok, "genesis": "x"},
                     {k: v for k, v in self.cfg_ok.items() if k != "espejo"}):
            with self.subTest(mala):
                self.cfg(mala)
                p = self.req()
                self.assertEqual(p.returncode, 2, p.stdout)
                self.assertFalse(os.path.exists(self.preq))
        self.cfg(self.cfg_ok)
        self.assertEqual(self.req().returncode, 0)

    def test_dos_peticiones_simultaneas_abren_una_sola_pr(self):
        """La reserva se toma antes de abrir la PR: una petición anidada en abrir_pr se rechaza."""
        llamadas = []
        a = type("A", (), {"abrir": True, "clon": "x", "ahora": fmt(NB - 30 * MIN)})()
        cfg = dict(self.cfg_ok)

        def abrir(*args, **kw):
            llamadas.append(1)
            self.assertEqual(mp._request(a, politica(), cfg, self.preq), mp.RECHAZADA)   # la «otra» petición
        original = mp.abrir_pr
        mp.abrir_pr = abrir
        try:
            self.assertEqual(mp._request(a, politica(), cfg, self.preq), 0)
        finally:
            mp.abrir_pr = original
        self.assertEqual(len(llamadas), 1)

    def test_configuracion_que_no_es_objeto_da_2_sin_traceback(self):
        self.cfg([1, 2])
        p = self.req()
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertNotIn("Traceback", p.stderr)
        self.assertFalse(os.path.exists(self.preq))


class FiltrosDeRamaDeGitHub(unittest.TestCase):
    """push_sin_filtro con la semántica de GitHub: `*` no cruza `/`, `!` niega, lo raro no cuenta."""

    def test_asterisco_simple_no_cruza_barra(self):
        self.assertFalse(mp.push_sin_filtro({"push": {"branches": ["*"]}}, "release/main"))
        self.assertTrue(mp.push_sin_filtro({"push": {"branches": ["*"]}}, "main"))
        self.assertTrue(mp.push_sin_filtro({"push": {"branches": ["**"]}}, "release/main"))

    def test_negacion_gana_el_ultimo(self):
        self.assertFalse(mp.push_sin_filtro({"push": {"branches": ["*", "!main"]}}, "main"))
        self.assertTrue(mp.push_sin_filtro({"push": {"branches": ["!main", "main"]}}, "main"))

    def test_branches_ignore(self):
        self.assertFalse(mp.push_sin_filtro({"push": {"branches-ignore": ["ma*"]}}, "main"))
        self.assertTrue(mp.push_sin_filtro({"push": {"branches-ignore": ["dev/*"]}}, "main"))

    def test_sintaxis_no_interpretada_no_cuenta_nunca(self):
        """Fail-closed en los dos sentidos: ni como coincidencia ni como «no ignorada»."""
        for on in ({"push": {"branches": ["ma?n"]}}, {"push": {"branches": ["[m]ain"]}},
                   {"push": {"branches-ignore": ["ma?n"]}}, {"push": {"branches-ignore": ["!main"]}}):
            with self.subTest(on):
                self.assertFalse(mp.push_sin_filtro(on, "main"))


class ResumenFiel(unittest.TestCase):
    """Lo que lee la operadora es lo que se aprueba: nada del objeto puede ocultarse con marcado."""

    def _repo(self, **c):
        return [{"repo": "org/savia", "base": "main", "include": ["docs/**"], "exclude": [],
                 "required_checks": ["CI"], **c}]

    def test_globs_con_marcado_rechazados(self):
        for g in ("<!--", "-->x", "a<b", "`x`", "a|b", "a b", "[x](y)", "a‮b", "docs/*?", "{a,b}"):
            with self.subTest(g), self.assertRaises(mp.Rechazada):
                mp.validar(politica(repos=self._repo(include=["docs/**", g])))

    def test_caso_de_codex_include_con_apertura_y_exclude_con_cierre(self):
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(repos=self._repo(include=["docs/**", "<!--", "src/**"], exclude=["-->"])))
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(repos=self._repo(exclude=["-->"])))

    def test_checks_y_reviewers_con_marcado(self):
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(repos=self._repo(required_checks=["<!-- CI"])))
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(reviewers=["revisora-a", "<!--"]))

    def test_resumen_sin_secuencias_de_comentario_html(self):
        pol = politica(repos=self._repo(include=["docs/**", "src/**"], exclude=["docs/x/**"],
                                        required_checks=["CI (lint) *"]))
        mp.validar(pol)
        resumen = mp.generar_resumen(pol)
        self.assertNotIn("<", resumen)
        self.assertNotIn("<", mp.generar_cuerpo(pol, resumen))
        self.assertIn("`src/**`", resumen)

    def test_md_escapa_el_marcado(self):
        self.assertNotIn("<!--", mp._md("a <!-- b --> c"))
        self.assertEqual(mp._md("<"), "&lt;")

    def test_reviewers_sin_distinguir_mayusculas(self):
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(reviewers=["Bob", "bob"]))
        with self.assertRaises(mp.Rechazada):
            mp.validar(politica(reviewers=["Savia-Orquestadora", "x"]))


class WorkflowsYPlan(unittest.TestCase):
    def _git(self, tmp, *a):
        subprocess.run(["git", "-C", tmp, "-c", "user.name=t", "-c", "user.email=t@x.invalid", *a], check=True)

    def test_workflow_en_subcarpeta_no_cuenta(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        self._git(tmp, "init", "-q", "-b", "main")
        for rel, esperado in ((".github/workflows/inert/ci.yml", []),
                              (".github/workflows/ci.yml", [".github/workflows/ci.yml"])):
            self._git(tmp, "rm", "-q", "-r", "-f", "--ignore-unmatch", ".github")
            ruta = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(ruta), exist_ok=True)
            with open(ruta, "w") as f:
                f.write("on: push\njobs: {}\n")
            self._git(tmp, "add", "-A")
            self._git(tmp, "commit", "-q", "--allow-empty", "-m", "x")
            self._git(tmp, "update-ref", "refs/remotes/origin/main", "HEAD")
            with self.subTest(rel):
                self.assertEqual(mp.workflow_sin_filtro(tmp, "main"), esperado)

    def test_repos_que_no_es_lista_da_rechazo_no_traceback(self):
        for repos in (5, True, "x", {"a": 1}):
            with self.subTest(repos), self.assertRaises(mp.Rechazada):
                mp.plan({"repos": repos, "max_merges": 3, "tiers": [1], "reviewers": ["a", "b"]}, NB, ".")


class AbrirPrIndiceAjeno(Base):
    def test_abrir_pr_no_publica_altas_ajenas_del_indice(self):
        remoto = os.path.join(self.tmp, "remoto2.git")
        subprocess.run(["git", "clone", "-q", "--bare", self.repo, remoto], check=True)
        clon = os.path.join(self.tmp, "clon2")
        subprocess.run(["git", "clone", "-q", remoto, clon], check=True)
        for k, val in (("user.name", "App"), ("user.email", "app@fixture.invalid")):
            subprocess.run(["git", "-C", clon, "config", k, val], check=True)
        with open(os.path.join(clon, "extra.txt"), "w") as f:
            f.write("ajeno\n")
        subprocess.run(["git", "-C", clon, "add", "extra.txt"], check=True)
        gh = os.path.join(self.tmp, "gh-ok")
        with open(gh, "w") as f:
            f.write("#!/usr/bin/env bash\nexit 0\n")
        os.chmod(gh, 0o755)
        os.environ["GH"] = gh
        pet = self.peticion()
        mp.abrir_pr(pet, clon, "org/aprobaciones")
        rama = "politica-" + os.path.basename(pet["ruta"])[:-5]
        ficheros = subprocess.run(["git", "-C", remoto, "show", "--name-only", "--format=", rama], check=True,
                                  capture_output=True, text=True).stdout.split()
        self.assertEqual(ficheros, [pet["ruta"]])


class Orquestadores(unittest.TestCase):
    def test_la_variable_amplia_la_lista_sin_desprohibir_a_las_de_siempre(self):
        viejo = os.environ.get("MERGE_SPRINT_ORCHESTRATOR")
        os.environ["MERGE_SPRINT_ORCHESTRATOR"] = "orq-x"
        try:
            for rv in (["revisora-a", "savia-orquestadora"], ["revisora-a", "savia-orchestrator"],
                       ["orq-x", "revisora-a"]):
                with self.subTest(rv), self.assertRaises(mp.Rechazada):
                    mp.validar(politica(reviewers=rv))
            mp.validar(politica())
        finally:
            if viejo is None:
                os.environ.pop("MERGE_SPRINT_ORCHESTRATOR", None)
            else:
                os.environ["MERGE_SPRINT_ORCHESTRATOR"] = viejo


COMPROBAR_AISLAMIENTO = r'''
import hashlib, importlib.util, sys
consumidor_py, compartido_py = sys.argv[1], sys.argv[2]
def cargar(nombre, ruta, registrar):
    spec = importlib.util.spec_from_file_location(nombre, ruta)
    mod = importlib.util.module_from_spec(spec)
    if registrar:
        sys.modules[nombre] = mod
    spec.loader.exec_module(mod)
    return mod
huella = lambda: hashlib.sha256(open(compartido_py, "rb").read()).hexdigest()
antes = huella()
# Otro consumidor ya tiene cargado el verificador compartido, con su nombre canónico.
otro = cargar("approval_receipt", compartido_py, registrar=True)
tipos, validar, ruta = otro.TIPOS, otro.validar_objeto, otro.RE_RUTA
c = cargar("consumidor_se512", consumidor_py, registrar=False)
assert "savia-politica" in c.ar.TIPOS, "el consumidor no habilitó el tipo"
assert c.ar is not otro, "el consumidor reutiliza el módulo de otro consumidor"
assert otro.TIPOS == tipos and "savia-politica" not in otro.TIPOS, "mutó el módulo de otro consumidor"
assert otro.validar_objeto is validar and otro.RE_RUTA is ruta, "mutó funciones del módulo de otro consumidor"
for nombre, m in list(sys.modules.items()):
    if m is not c.ar and "savia-politica" in getattr(m, "TIPOS", ()):
        raise AssertionError(f"tipo visible en el módulo {nombre}")
limpio = cargar("approval_receipt_limpio", compartido_py, registrar=False)
assert "savia-politica" not in limpio.TIPOS, "el fichero compartido trae el tipo"
assert huella() == antes, "el fichero compartido cambió"
print("AISLADO")
'''


class AislamientoDelTipo(unittest.TestCase):
    """El tipo `savia-politica` existe solo en la copia del consumidor (en un proceso limpio)."""

    def _comprobar(self, consumidor, compartido):
        return subprocess.run([sys.executable, "-c", COMPROBAR_AISLAMIENTO, consumidor, compartido],
                              capture_output=True, text=True)

    def test_tipo_solo_habilitado_en_la_copia_del_consumidor(self):
        p = self._comprobar(SCRIPT, os.path.join(ROOT, "scripts", "approval-receipt.py"))
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("AISLADO", p.stdout)

    def test_la_comprobacion_detecta_un_consumidor_que_reutiliza_el_modulo_compartido(self):
        """Mutante: cargar_verificador devuelve el módulo ya importado por otro consumidor."""
        with open(SCRIPT) as f:
            src = f.read()
        original = "def cargar_verificador():\n"
        self.assertIn(original, src)
        mutante = src.replace(original, original + '    if "approval_receipt" in sys.modules:\n'
                                                   '        return sys.modules["approval_receipt"]\n', 1)
        with tempfile.TemporaryDirectory() as d:
            shutil.copy(os.path.join(ROOT, "scripts", "approval-receipt.py"), d)
            with open(os.path.join(d, "merge-sprint-policy.py"), "w") as f:
                f.write(mutante)
            p = self._comprobar(os.path.join(d, "merge-sprint-policy.py"), os.path.join(d, "approval-receipt.py"))
        self.assertNotEqual(p.returncode, 0, p.stdout)
        self.assertIn("reutiliza el módulo", p.stderr)


class Entorno(Base):
    """CLI con PATH sin gpg o sin git: sin grant (3)."""

    def _cli(self, path):
        pet = self.peticion()
        self.aprobar_pet(pet)
        home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(home, "policy"))
        with open(os.path.join(home, "policy", f"{self.pol_obj['id']}.request.json"), "w") as f:
            json.dump(pet, f)
        fp, fc = os.path.join(self.tmp, "p.json"), os.path.join(self.tmp, "c.json")
        with open(fp, "w") as f:
            f.write(mp.canonico(self.pol_obj))
        with open(fc, "w") as f:
            json.dump(self.cfg, f)
        env = {**os.environ, "PATH": path}
        return subprocess.run([sys.executable, SCRIPT, "--home", home, "verify", "--politica", fp,
                               "--aprobacion", fc, "--ahora", fmt(NB + H)], env=env, capture_output=True, text=True)

    def _bin(self, *progs):
        d = os.path.join(self.tmp, "bin-" + "-".join(progs or ("nada",)))
        os.makedirs(d)
        for p in progs:
            os.symlink(shutil.which(p), os.path.join(d, p))
        return d

    def test_cli_con_todo_da_grant(self):
        p = self._cli(os.environ["PATH"])
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def test_sin_gpg(self):
        p = self._cli(self._bin("git"))
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)
        self.assertIn("gpg", p.stdout)

    def test_sin_git(self):
        p = self._cli(self._bin("gpg"))
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)


if __name__ == "__main__":
    unittest.main()
