"""SE-518 A1 / S1n: revisión diaria de la comprobación nocturna (AC-33 a AC-39).

Stdlib pura (unittest). Cada AC tiene su caso negativo o límite. La consulta se
simula con un `runner` inyectado (nada de red); la CLI se prueba de extremo a
extremo con un `gh` falso en el PATH. Los repositorios y flujos de las pruebas
son inventados (acme/widgets).
"""
import datetime as dt
import json
import os
import re
import stat
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REPO_REAL = os.path.dirname(os.path.dirname(PROJECT))
sys.path.insert(0, PROJECT)
sys.path.insert(0, HERE)

from pulse import backup, events, nocturna, status, store  # noqa: E402
from pulse.store import EntradaInvalida, PulseError  # noqa: E402
from test_pulse import Base, leer  # noqa: E402

UTC = dt.timezone.utc
ENV = {"PULSE_NOCTURNA_REPO": "acme/widgets", "PULSE_NOCTURNA_FLUJO": "Suite nocturna"}
URL = "https://forge.example/acme/widgets/actions/runs/42"
T0 = dt.datetime(2026, 3, 10, 8, 0, 0, tzinfo=UTC)
INSTALA = re.compile(r"\b(?:systemctl|loginctl)\b")  # los .example no nombran ninguna orden de instalación


def corrida(edad, conclusion="failure", status_="completed", url=URL, dias=0, **extra):
    """Una ejecución del forge creada hace `edad` (timedelta) respecto a la pasada de T0 + `dias` días."""
    d = {"status": status_, "conclusion": conclusion,
         "createdAt": store.fmt(T0 + dt.timedelta(days=dias) - edad), "url": url, "headBranch": "main"}
    d.update(extra)
    return d


def horas(h, m=0):
    return dt.timedelta(hours=h, minutes=m)


def respuesta(*corridas, rc=0, stderr=""):
    def runner(argv, timeout):
        runner.llamadas.append(list(argv))
        return subprocess.CompletedProcess(argv, rc, json.dumps(list(corridas)), stderr)
    runner.llamadas = []
    return runner


def cruda(stdout="", rc=0, stderr=""):
    def runner(argv, timeout):
        runner.llamadas.append(list(argv))
        return subprocess.CompletedProcess(argv, rc, stdout, stderr)
    runner.llamadas = []
    return runner


def falla(exc):
    def runner(argv, timeout):
        runner.llamadas.append(list(argv))
        raise exc
    runner.llamadas = []
    return runner


class NocturnaBase(Base):
    def paso(self, runner, dias=0, env=ENV):
        """Una pasada en T0 + `dias` días."""
        return nocturna.comprobar(self.root, ahora=T0 + dt.timedelta(days=dias), env=env, runner=runner)

    def comprobadas(self):
        return [e for e in self.ledger() if e["tipo"] == "nocturna_comprobada"]

    def cerradas(self):
        return [e for e in self.ledger() if e["tipo"] == "nocturna_racha_cerrada"]

    def peticiones_noct(self, dias=0):
        t = T0 + dt.timedelta(days=dias)
        return [p for p in backup.pendientes(self.root, ahora=t, incluir_respaldo=True) if p["id"].startswith("nocturna-")]

    def ids_en_fichero(self):
        """Ids en peticiones.json sin filtrar por caducidad (los relojes de las pruebas no son el real)."""
        try:
            return [p["id"] for p in json.loads(leer(self.root + "/peticiones.json"))["peticiones"]]
        except FileNotFoundError:
            return []

    def rojo(self, dias=0, **kw):
        return self.paso(respuesta(corrida(horas(5), dias=dias, **kw)), dias)

    def verde(self, dias=0, h=2):
        return self.paso(respuesta(corrida(horas(h), "success", dias=dias)), dias)


class Verde(NocturnaBase):  # AC-33
    def test_verde_reciente_una_linea_y_ninguna_peticion(self):
        accion, ev = self.paso(respuesta(corrida(horas(7), "success")))
        self.assertEqual((accion, ev["resultado"], ev["racha"]), ("verde", "verde", 0))
        self.assertEqual(self.peticiones_noct(), [])
        d = status.collect(self.root, ahora=T0, env=ENV)
        self.assertEqual(d["pendientes"], [])
        self.assertIn("Comprobación nocturna: bien (última ejecución hace 7 h).", status.render(d))

    def test_verde_de_mas_de_26_h_no_cuenta_como_verde(self):
        accion, ev = self.paso(respuesta(corrida(horas(26, 1), "success")))
        self.assertEqual(ev["resultado"], "sin_ejecucion")
        self.assertEqual(len(self.peticiones_noct()), 1)
        self.assertNotIn("Comprobación nocturna: bien", status.render(status.collect(self.root, ahora=T0, env=ENV)))

    def test_verde_no_dice_bien_si_la_ultima_pasada_es_vieja(self):
        self.paso(respuesta(corrida(horas(7), "success")))
        d = status.collect(self.root, ahora=T0 + horas(27), env=ENV)
        linea = [l for l in status.render(d).splitlines() if l.startswith("Comprobación nocturna")][0]
        self.assertNotIn("Comprobación nocturna: bien", linea)
        self.assertIn("no sé", linea)

    def test_ejecucion_en_curso_se_ignora_y_manda_la_ultima_terminada(self):
        r = respuesta(corrida(horas(1), "", status_="in_progress"), corrida(horas(9), "success"))
        self.assertEqual(self.paso(r)[1]["resultado"], "verde")

    def test_solo_en_curso_es_sin_ejecucion(self):
        r = respuesta(corrida(horas(1), "", status_="in_progress"))
        self.assertEqual(self.paso(r)[1]["resultado"], "sin_ejecucion")

    def test_elige_la_mas_nueva_aunque_vengan_desordenadas(self):
        r = respuesta(corrida(horas(20), "success"), corrida(horas(3), "failure"))
        self.assertEqual(self.paso(r)[1]["resultado"], "rojo")


class Rojo(NocturnaBase):  # AC-34
    def test_fallo_genera_peticion_con_las_cinco_cosas_fuera_de_avisos(self):
        accion, ev = self.rojo()
        self.assertEqual((accion, ev["resultado"], ev["racha"], ev["conclusion"]), ("rojo", "rojo", 1, "failure"))
        (p,) = self.peticiones_noct()
        for campo in ("que", "por_que_ahora", "si_no_contestas", "si_aplazas", "caduca"):
            self.assertTrue(p[campo])
        self.assertIn("anoche", p["que"])
        self.assertIn(URL, p["que"])
        self.assertFalse(backup.es_aviso(p))
        d = status.collect(self.root, ahora=T0, env=ENV)
        self.assertEqual(d["avisos"], 0)
        self.assertEqual(len(d["pendientes"]), 1)
        self.assertIn("Esperan algo de ti: 1", status.render(d))

    def test_cancelada_cuenta_igual_que_fallo(self):
        accion, ev = self.rojo(conclusion="cancelled")
        self.assertEqual((ev["resultado"], ev["racha"], ev["conclusion"]), ("rojo", 1, "cancelled"))
        (p,) = self.peticiones_noct()
        self.assertIn("canceló", p["que"])
        self.assertFalse(backup.es_aviso(p))

    def test_otras_conclusiones_que_no_son_success_tambien_son_rojo(self):
        for concl in ("timed_out", "skipped", "neutral", "startup_failure", "action_required", "stale"):
            with self.subTest(concl):
                self.setUp()
                self.assertEqual(self.rojo(conclusion=concl)[1]["resultado"], "rojo")

    def test_conclusion_desconocida_es_rojo_no_verde(self):
        accion, ev = self.rojo(conclusion="algo_nuevo")
        self.assertEqual((ev["resultado"], ev["conclusion"]), ("rojo", "otra"))

    def test_conclusion_vacia_en_ejecucion_terminada_no_es_verde(self):
        self.assertEqual(self.rojo(conclusion="")[1]["resultado"], "rojo")

    def test_enlace_inseguro_no_entra_en_la_peticion(self):
        self.rojo(url="javascript:alert(1)")
        (p,) = self.peticiones_noct()
        self.assertNotIn("javascript", json.dumps(p))
        self.setUp()
        self.rojo(url="https://x.example/\x1b[31mrojo")
        self.assertNotIn("\x1b", json.dumps(self.peticiones_noct()))

    def test_la_peticion_valida_contra_el_contrato(self):
        self.rojo()
        self.assertEqual(self.cli("validate", "peticiones", self.root + "/peticiones.json").returncode, 0)
        self.assertTrue(self.comprobadas())
        self.assertEqual(self.cli("validate", "evento", self.root + "/eventos.jsonl").returncode, 0)


class Racha(NocturnaBase):  # AC-35
    def test_el_contador_sube_cada_dia_y_la_peticion_se_renueva(self):
        for n in (1, 2, 3, 4, 5):
            ev = self.rojo(dias=n - 1)[1]
            self.assertEqual(ev["racha"], n)
        (p,) = self.peticiones_noct(dias=4)
        self.assertIn("5 noches seguidas", p["que"])
        self.assertIn("noche 6", p["si_no_contestas"])
        self.assertEqual(p["id"], "nocturna-20260314")

    def test_una_sola_peticion_nocturna_vigente_aunque_pasen_los_dias(self):
        for n in range(3):
            self.rojo(dias=n)
        self.assertEqual(self.ids_en_fichero(), ["nocturna-20260312"])

    def test_la_peticion_nocturna_vigente_de_ayer_se_sustituye_y_las_ajenas_se_respetan(self):
        self.publica(self.peticion("nocturna-20260309"), self.peticion("otra-cosa"))
        self.rojo(0)
        self.assertEqual(sorted(self.ids_en_fichero()), ["nocturna-20260310", "otra-cosa"])
        self.publica(self.peticion("nocturna-20260309"), self.peticion("otra-cosa"))
        self.verde(1)
        self.assertEqual(self.ids_en_fichero(), ["otra-cosa"])

    def test_noche_uno_dice_anoche_no_1_noches(self):
        self.rojo()
        (p,) = self.peticiones_noct()
        self.assertIn("anoche", p["que"])
        self.assertNotRegex(p["que"], r"\b1 noches")
        self.assertNotIn("1 noche", p["que"])
        self.assertIn("noche 2", p["si_no_contestas"])

    def test_pasada_repetida_el_mismo_dia_no_suma_noche(self):
        self.rojo()
        accion, ev = self.paso(respuesta(corrida(horas(5))), 0)
        self.assertEqual((accion, ev), ("nada", None))
        self.assertEqual([e["racha"] for e in self.comprobadas()], [1])
        self.assertEqual(len(self.peticiones_noct()), 1)
        self.assertIn("anoche", self.peticiones_noct()[0]["que"])

    def test_pasada_repetida_otro_dia_si_suma(self):
        self.rojo(0)
        self.assertEqual(self.rojo(1)[1]["racha"], 2)

    def test_rojo_tras_verde_el_mismo_dia_vuelve_a_empezar_en_uno(self):
        self.rojo(0)
        self.paso(respuesta(corrida(horas(1), "success")), 0)
        self.assertEqual(self.rojo(0)[1]["racha"], 1)

    def test_la_racha_sale_del_ledger_no_de_memoria(self):
        self.rojo(0)
        self.rojo(1)
        self.assertEqual(nocturna.estado(self.ledger())["racha"], 2)


class SinEjecucion(NocturnaBase):  # AC-36
    def test_sin_ninguna_ejecucion_hay_peticion(self):
        accion, ev = self.paso(respuesta())
        self.assertEqual((ev["resultado"], ev["racha"]), ("sin_ejecucion", 1))
        (p,) = self.peticiones_noct()
        self.assertIn("no se ha ejecutado en las últimas 26 horas", p["que"])
        self.assertFalse(backup.es_aviso(p))

    def test_limite_25h59_no_hay_peticion(self):
        accion, ev = self.paso(respuesta(corrida(horas(25, 59), "success")))
        self.assertEqual(ev["resultado"], "verde")
        self.assertEqual(self.peticiones_noct(), [])

    def test_limite_26h01_si_hay_peticion(self):
        accion, ev = self.paso(respuesta(corrida(horas(26, 1), "success")))
        self.assertEqual(ev["resultado"], "sin_ejecucion")
        self.assertEqual(len(self.peticiones_noct()), 1)

    def test_limite_exacto_26h_cuenta_como_reciente(self):
        self.assertEqual(self.paso(respuesta(corrida(horas(26), "success")))[1]["resultado"], "verde")

    def test_una_ejecucion_vieja_en_rojo_es_sin_ejecucion(self):
        self.assertEqual(self.paso(respuesta(corrida(horas(30), "failure")))[1]["resultado"], "sin_ejecucion")

    def test_ejecucion_con_fecha_futura_no_es_verde(self):
        accion, ev = self.paso(respuesta(corrida(-horas(2), "success")))
        self.assertEqual((ev["resultado"], ev["motivo"]), ("no_consultable", "respuesta_ilegible"))


class NoConsultable(NocturnaBase):  # AC-37
    def casos(self):
        return {
            "herramienta_ausente": falla(FileNotFoundError(2, "No such file", "gh")),
            "sin_sesion": cruda(rc=4, stderr="To get started with GitHub CLI, please run:  gh auth login"),
            "tiempo_agotado": falla(subprocess.TimeoutExpired(["gh"], 60)),
            "respuesta_ilegible": cruda("esto no es json"),
            "consulta_fallida": cruda(rc=1, stderr="error de red"),
        }

    def test_cada_fallo_de_consulta_es_peticion_no_pass(self):
        for motivo, runner in self.casos().items():
            with self.subTest(motivo):
                self.setUp()
                accion, ev = self.paso(runner)
                self.assertEqual((accion, ev["resultado"], ev["motivo"]), ("no_consultable", "no_consultable", motivo))
                (p,) = self.peticiones_noct()
                self.assertIn("No he podido mirar la comprobación nocturna", p["que"])
                self.assertIn("No sé si está bien", p["que"])
                self.assertFalse(backup.es_aviso(p))
                linea = [l for l in status.render(status.collect(self.root, ahora=T0, env=ENV)).splitlines()
                         if l.startswith("Comprobación nocturna")][0]
                self.assertNotIn("Comprobación nocturna: bien", linea)

    def test_respuestas_ilegibles_variadas(self):
        for crudo in ("{}", "[1, 2]", '[{"status": "completed"}]', '[{"status":"completed","conclusion":"success","createdAt":"ayer","url":"u"}]',
                      "", "null", '[{"status":"completed","conclusion":7,"createdAt":"2026-03-10T07:00:00Z","url":"u"}]'):
            with self.subTest(crudo):
                self.setUp()
                ev = self.paso(cruda(crudo))[1]
                self.assertEqual((ev["resultado"], ev["motivo"]), ("no_consultable", "respuesta_ilegible"))

    def test_un_fallo_de_consulta_tras_un_rojo_no_reinicia_el_contador(self):
        self.rojo(0)
        self.rojo(1)
        ev = self.paso(falla(FileNotFoundError(2, "x", "gh")), 2)[1]
        self.assertEqual((ev["resultado"], ev["racha"]), ("no_consultable", 2))
        (p,) = self.peticiones_noct(dias=2)
        self.assertIn("2 noches", p["que"])
        self.assertEqual(self.cerradas(), [])
        self.assertEqual(self.rojo(3)[1]["racha"], 3)

    def test_el_fallo_de_consulta_no_suma_noche(self):
        self.rojo(0)
        self.paso(falla(FileNotFoundError(2, "x", "gh")), 1)
        self.paso(falla(FileNotFoundError(2, "x", "gh")), 2)
        self.assertEqual(nocturna.estado(self.ledger())["racha"], 1)

    def test_sin_racha_previa_el_fallo_de_consulta_no_inventa_racha(self):
        self.assertEqual(self.paso(falla(FileNotFoundError(2, "x", "gh")))[1]["racha"], 0)

    def test_la_salida_de_gh_no_llega_al_ledger_ni_a_las_peticiones(self):
        marca = "TOKEN-SECRETO-ghp_abc123"
        self.paso(cruda(rc=1, stderr=marca))
        self.assertNotIn(marca, leer(self.root + "/eventos.jsonl") + leer(self.root + "/peticiones.json"))

    def test_peticiones_ilegibles_no_anotan_nada(self):
        self.write("peticiones.json", "{roto", 0o600)
        with self.assertRaises(PulseError):
            self.rojo()
        self.assertFalse(os.path.exists(self.root + "/eventos.jsonl"))


class Configuracion(NocturnaBase):  # AC-38
    def test_sin_configuracion_no_se_consulta_nada_y_status_lo_dice(self):
        r = respuesta(corrida(horas(1), "success"))
        for env in ({}, {"PULSE_NOCTURNA_REPO": "acme/widgets"}, {"PULSE_NOCTURNA_FLUJO": "x"},
                    {"PULSE_NOCTURNA_REPO": "", "PULSE_NOCTURNA_FLUJO": "x"}):
            with self.subTest(env):
                with self.assertRaises(PulseError) as cm:
                    self.paso(r, env=env)
                self.assertNotIsInstance(cm.exception, EntradaInvalida)
        self.assertEqual(r.llamadas, [])
        self.assertFalse(os.path.exists(self.root + "/eventos.jsonl"))
        txt = status.render(status.collect(self.root, ahora=T0, env={}))
        self.assertIn("Comprobación nocturna: sin configurar", txt)
        self.assertIn("no consulto nada", txt)
        self.assertNotIn("Comprobación nocturna: bien", txt)

    def test_con_configuracion_y_sin_datos_status_no_dice_bien(self):
        linea = [l for l in status.render(status.collect(self.root, ahora=T0, env=ENV)).splitlines()
                 if l.startswith("Comprobación nocturna")][0]
        self.assertIn("todavía no se ha comprobado", linea)

    def test_valores_con_forma_de_opcion_o_con_espacios_raros_se_rechazan(self):
        for repo in ("--repo=x/y", "-x/y", "acme", "acme/widgets extra", "acme/widgets;ls", "a/b/c/d/e", "$(id)/x"):
            with self.subTest(repo):
                r = respuesta()
                with self.assertRaises(EntradaInvalida):
                    self.paso(r, env={"PULSE_NOCTURNA_REPO": repo, "PULSE_NOCTURNA_FLUJO": "f"})
                self.assertEqual(r.llamadas, [])
        for flujo in ("-w", "--json", "x\ny", "a" * 101, "x;y"):
            with self.subTest(flujo):
                with self.assertRaises(EntradaInvalida):
                    self.paso(respuesta(), env={"PULSE_NOCTURNA_REPO": "acme/widgets", "PULSE_NOCTURNA_FLUJO": flujo})

    def test_acepta_host_y_nombres_de_fichero_de_flujo(self):
        r = respuesta(corrida(horas(1), "success"))
        self.paso(r, env={"PULSE_NOCTURNA_REPO": "ghe.example.org/acme/widgets", "PULSE_NOCTURNA_FLUJO": "nightly.yml"})
        self.assertEqual(len(r.llamadas), 1)

    def test_la_consulta_es_exactamente_gh_run_list_de_solo_lectura(self):
        r = respuesta(corrida(horas(1), "success"))
        self.paso(r)
        (argv,) = r.llamadas
        self.assertEqual(argv[:3], ["gh", "run", "list"])
        self.assertEqual(argv[argv.index("--repo") + 1], "acme/widgets")
        self.assertEqual(argv[argv.index("--workflow") + 1], "Suite nocturna")
        self.assertEqual(argv[argv.index("--branch") + 1], "main")  # rama por defecto
        self.assertIn("headBranch", argv[argv.index("--json") + 1].split(","))

    def test_la_rama_sale_de_configuracion(self):
        r = respuesta(corrida(horas(1), "success", headBranch="trunk"))
        self.assertEqual(self.paso(r, env=dict(ENV, PULSE_NOCTURNA_RAMA="trunk"))[0], "verde")
        (argv,) = r.llamadas
        self.assertEqual(argv[argv.index("--branch") + 1], "trunk")
        for rama in ("-x", "--json", "a b", "x;y", "a" * 101):
            with self.subTest(rama):
                r = respuesta()
                with self.assertRaises(EntradaInvalida):
                    self.paso(r, env=dict(ENV, PULSE_NOCTURNA_RAMA=rama))
                self.assertEqual(r.llamadas, [])

    def test_un_verde_en_otra_rama_no_tapa_el_rojo_de_la_rama_vigilada(self):
        # una ejecución manual en otra rama, más reciente y en verde, no cuenta
        r = respuesta(corrida(horas(1), "success", headBranch="parche-que-pasa"), corrida(horas(5), "failure"))
        self.assertEqual(self.paso(r)[0], "rojo")
        self.setUp()
        r = respuesta(corrida(horas(1), "success", headBranch="parche-que-pasa"))
        self.assertEqual(self.paso(r)[0], "sin_ejecucion")

    def test_sin_rama_en_la_respuesta_no_se_fia(self):
        c = corrida(horas(1), "success")
        del c["headBranch"]
        self.assertEqual(self.paso(respuesta(c))[0], "no_consultable")
        self.assertEqual(self.comprobadas()[0]["motivo"], "respuesta_ilegible")

    def test_la_fuente_se_niega_a_ejecutar_cualquier_otra_orden_de_gh(self):
        for argv in (["run", "rerun", "1"], ["run", "cancel", "1"], ["workflow", "run", "x"], ["api", "-X", "POST", "/x"],
                     ["pr", "merge", "1"], ["run", "delete", "1"], [], ["run"]):
            with self.subTest(argv):
                r = cruda("[]")
                with self.assertRaises(PulseError):
                    nocturna._gh(argv, runner=r)
                self.assertEqual(r.llamadas, [])

    def test_ningun_nombre_de_repositorio_ni_de_flujo_concretos_en_el_codigo(self):
        prohibidos = ["Nightly " + "full BATS", "nightly-full-" + "bats"]
        try:
            url = subprocess.run(["git", "-C", REPO_REAL, "remote", "get-url", "origin"], capture_output=True,
                                 text=True, timeout=10).stdout.strip()
            m = re.search(r"[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_-]+?)(?:\.git)?$", url)
            if m:
                prohibidos.append(m.group(1))
        except (OSError, subprocess.SubprocessError):
            pass
        ficheros = [os.path.join(PROJECT, "pulse", "nocturna.py"), os.path.abspath(__file__),
                    os.path.join(PROJECT, "CLAUDE.md")]
        ficheros += [os.path.join(PROJECT, "systemd", f) for f in sorted(os.listdir(os.path.join(PROJECT, "systemd")))]
        for f in ficheros:
            txt = leer(f)
            for p in prohibidos:
                self.assertNotIn(p.lower(), txt.lower(), "%s contiene %s" % (os.path.basename(f), p))

    def test_estatico_la_fuente_solo_nombra_run_list(self):
        src = leer(os.path.join(PROJECT, "pulse", "nocturna.py"))
        for palabra in ("rerun", "gh run cancel", "workflow run", "pr merge", "--method", "POST", "PATCH", "DELETE", "gh api", '"api"', '"delete"'):
            self.assertNotIn(palabra, src, palabra)
        self.assertEqual(nocturna._PERMITIDO, (("run", "list"),))


class Cierre(NocturnaBase):  # AC-39
    def test_volver_a_verde_cierra_la_peticion_y_anota_la_longitud(self):
        for n in range(3):
            self.rojo(n)
        accion, ev = self.verde(3)
        self.assertEqual((accion, ev["resultado"], ev["racha"]), ("verde", "verde", 0))
        self.assertEqual(self.ids_en_fichero(), [])
        (c,) = self.cerradas()
        self.assertEqual(c["longitud"], 3)
        self.assertIn("3 noches", status.render(status.collect(self.root, ahora=T0 + dt.timedelta(days=3), env=ENV)))

    def test_una_racha_cerrada_no_reaparece_al_dia_siguiente(self):
        self.rojo(0)
        self.verde(1)
        self.verde(2)
        self.assertEqual(len(self.cerradas()), 1)
        self.assertEqual(self.peticiones_noct(dias=2), [])
        self.assertEqual(nocturna.estado(self.ledger())["racha"], 0)

    def test_la_longitud_de_la_racha_cerrada_solo_se_dice_el_dia_del_cierre(self):
        self.rojo(0)
        self.verde(1)
        self.verde(2)
        d = status.collect(self.root, ahora=T0 + dt.timedelta(days=2), env=ENV)
        self.assertNotIn("racha", status.render(d).split("Comprobación nocturna")[1].split("\n")[0])

    def test_una_peticion_nocturna_nunca_es_aviso_aunque_diga_que_no_hay_nada_que_hacer(self):
        p = self.peticion("nocturna-20260310", si_no_contestas=events.NADA_QUE_HACER)
        self.assertFalse(backup.es_aviso(p))
        self.assertTrue(backup.es_aviso(self.peticion("aviso-run-x-1", si_no_contestas=events.NADA_QUE_HACER)))

    def test_verde_repetido_el_mismo_dia_no_duplica_nada(self):
        self.rojo(0)
        self.verde(1)
        accion, ev = self.verde(1)
        self.assertEqual((accion, ev), ("nada", None))
        self.assertEqual(len(self.cerradas()), 1)

    def test_tras_cerrar_un_nuevo_rojo_empieza_en_uno(self):
        for n in range(3):
            self.rojo(n)
        self.verde(3)
        self.assertEqual(self.rojo(4)[1]["racha"], 1)

    def test_verde_sin_racha_previa_no_anota_cierre(self):
        self.paso(respuesta(corrida(horas(2), "success")))
        self.assertEqual(self.cerradas(), [])

    def test_el_verde_no_borra_otras_peticiones(self):
        self.publica(self.peticion("otra-cosa"))
        self.rojo(0)
        self.verde(1)
        ids = [p["id"] for p in backup.pendientes(self.root, ahora=T0 + dt.timedelta(days=1), incluir_respaldo=True)]
        self.assertEqual(ids, ["otra-cosa"])

    def test_ledger_ilegible_no_da_verde_ni_cierra_nada(self):
        self.rojo(0)
        os.chmod(self.root + "/eventos.jsonl", 0o666)  # escribible por otros: el ledger no es fiable
        with self.assertRaises(PulseError):
            self.verde(1)


class Esquema(NocturnaBase):
    def test_los_eventos_nuevos_tienen_esquema_y_rechazan_valores_fuera_del_conjunto(self):
        from pulse import schema
        sch = schema.load_schema("evento")
        base = {"schema_version": "1", "id": "ev-0123456789abcdef", "at": "2026-03-10T08:00:00Z", "clase": "ninguna",
                "entrega": "ninguna", "nivel": "N4"}
        bueno = dict(base, tipo="nocturna_comprobada", resultado="rojo", dia="2026-03-10", racha=2, conclusion="failure")
        self.assertEqual(schema.validate(bueno, sch), [])
        for malo in (dict(bueno, resultado="quizas"), dict(bueno, dia="ayer"), dict(bueno, racha=-1),
                     dict(bueno, conclusion="texto libre de la ejecución"), dict(bueno, motivo="otro"),
                     {k: v for k, v in bueno.items() if k != "racha"}):
            self.assertNotEqual(schema.validate(malo, sch), [], malo)
        cierre = dict(base, tipo="nocturna_racha_cerrada", longitud=3, dia="2026-03-10")
        self.assertEqual(schema.validate(cierre, sch), [])
        self.assertNotEqual(schema.validate(dict(cierre, longitud=0), sch), [])

    def test_el_ledger_no_lleva_url_ni_repositorio_ni_flujo(self):
        self.rojo()
        txt = leer(self.root + "/eventos.jsonl")
        for ajeno in (URL, "acme", "widgets", "Suite nocturna"):
            self.assertNotIn(ajeno, txt)


class CLI(NocturnaBase):
    def gh_falso(self, cuerpo):
        d = os.path.join(self._tmp.name, "bin")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "gh")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\n" + cuerpo)
        os.chmod(p, 0o755)
        return d

    def env_cli(self, bindir, **extra):
        env = dict(self.env, PATH=bindir + ":" + os.environ["PATH"], **ENV)
        env.update(extra)
        return env

    def salida_gh(self, edad_h, conclusion):
        t = dt.datetime.now(UTC) - dt.timedelta(hours=edad_h)
        return json.dumps([{"status": "completed", "conclusion": conclusion, "createdAt": store.fmt(t), "url": URL,
                            "headBranch": "main"}])

    def test_orden_nocturna_rojo_deja_peticion_y_sale_con_0(self):
        b = self.gh_falso("cat <<'EOF'\n%s\nEOF\n" % self.salida_gh(5, "failure"))
        r = self.cli("nocturna", env=self.env_cli(b))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("anoche", r.stdout)
        s = self.cli("status", env=self.env_cli(b))
        self.assertIn("Esperan algo de ti: 1", s.stdout)
        self.assertIn("en rojo", s.stdout)
        i = self.cli("inbox", env=self.env_cli(b)).stdout
        self.assertIn("Pendiente de ti (1)", i)
        self.assertNotIn("Avisos, no piden nada", i)

    def test_orden_nocturna_verde(self):
        b = self.gh_falso("cat <<'EOF'\n%s\nEOF\n" % self.salida_gh(5, "success"))
        r = self.cli("nocturna", env=self.env_cli(b))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("bien", r.stdout)
        self.assertIn("Esperan algo de ti: nada que conste", self.cli("status", env=self.env_cli(b)).stdout)

    def test_repetida_el_mismo_dia_no_suma_noche_por_la_cli(self):
        b = self.gh_falso("cat <<'EOF'\n%s\nEOF\n" % self.salida_gh(5, "failure"))
        self.cli("nocturna", env=self.env_cli(b))
        r = self.cli("nocturna", env=self.env_cli(b))
        self.assertIn("Sin cambios", r.stdout)
        self.assertEqual([e["racha"] for e in self.comprobadas()], [1])

    def test_sin_gh_en_el_path_hay_peticion_y_sale_con_0(self):
        vacio = os.path.join(self._tmp.name, "vacio")
        os.makedirs(vacio)
        env = dict(self.env, PATH=vacio, **ENV)
        codigo = "import sys; sys.path.insert(0, %r); from pulse.cli import main; sys.exit(main(['nocturna']))" % PROJECT
        r = subprocess.run([sys.executable, "-c", codigo], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("No he podido mirar", r.stdout)
        self.assertEqual(self.comprobadas()[0]["motivo"], "herramienta_ausente")

    def test_sin_configuracion_sale_con_1_y_no_lanza_gh(self):
        marca = os.path.join(self._tmp.name, "llamado")
        b = self.gh_falso("touch %s\necho '[]'\n" % marca)
        env = dict(self.env, PATH=b + ":" + os.environ["PATH"])
        r = self.cli("nocturna", env=env)
        self.assertEqual(r.returncode, 1)
        self.assertIn("PULSE_NOCTURNA_REPO", r.stderr)
        self.assertFalse(os.path.exists(marca))

    def test_configuracion_invalida_sale_con_2(self):
        b = self.gh_falso("echo '[]'\n")
        r = self.cli("nocturna", env=self.env_cli(b, PULSE_NOCTURNA_REPO="--json"))
        self.assertEqual(r.returncode, 2)

    def test_el_timeout_de_la_consulta_es_finito(self):
        self.assertTrue(0 < nocturna.TIMEOUT_S <= 120)


class Ejemplos(unittest.TestCase):
    def test_unidad_y_temporizador_de_ejemplo_existen_y_no_se_instalan(self):
        d = os.path.join(PROJECT, "systemd")
        unidad = leer(os.path.join(d, "pulse-nocturna.service.example"))
        temp = leer(os.path.join(d, "pulse-nocturna.timer.example"))
        self.assertIn("ExecStart=", unidad)
        self.assertIn("pulse nocturna", unidad)
        self.assertIn("EnvironmentFile=", unidad)
        self.assertIn("Persistent=true", temp)
        self.assertIn("OnCalendar=", temp)
        self.assertIn("WantedBy=timers.target", temp)
        # ejemplo, no instalado: ninguna orden que lo instale ni ruta personal
        for txt in (unidad, temp):
            self.assertNotRegex(txt, r"/home/[a-z]")
            self.assertIsNone(INSTALA.search(txt), INSTALA.pattern)

    def test_el_detector_de_ordenes_de_instalacion_no_es_ciego(self):
        for orden in ("ExecStartPre=systemctl --user enable pulse-nocturna.timer", "systemctl start x",
                      "ExecStartPost=/usr/bin/systemctl --user daemon-reload", "loginctl enable-linger"):
            with self.subTest(orden):
                self.assertIsNotNone(INSTALA.search(orden))
        self.assertIsNone(INSTALA.search("# Ver README.md de esta carpeta."))

    def test_ninguna_unidad_activa_en_el_repo(self):
        d = os.path.join(PROJECT, "systemd")
        for f in os.listdir(d):
            self.assertTrue(f.endswith(".example") or f == "README.md", f)


if __name__ == "__main__":
    unittest.main()
