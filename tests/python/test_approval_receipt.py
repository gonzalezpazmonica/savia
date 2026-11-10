#!/usr/bin/env python3
"""Tests de scripts/approval-receipt.py (SE-488 S1: R1 artefacto, R2 recibo de merge).

Fixture: un repo de aprobaciones local con génesis propio; los merges se firman con
una clave GPG de prueba que hace de web-flow. Un test por condición de R2 (AC-1),
lote/concurrencia/acción fallida (AC-1b) y fail-closed de entorno (AC-2).
"""
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
SCRIPT = os.path.join(ROOT, "scripts", "approval-receipt.py")
_spec = importlib.util.spec_from_file_location("approval_receipt", SCRIPT)
ar = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ar)

T0 = dt.datetime(2026, 11, 10, 10, 0, 0, tzinfo=dt.timezone.utc)
H = dt.timedelta(hours=1)
OPERADORA = ("Operadora Fixture", "operadora@fixture.invalid")
BOT = ("approvals-app[bot]", "bot@fixture.invalid")
REPO = "org/savia"
SHA_A = "a" * 40
SHA_B = "b" * 40


def _git_env(gnupghome):
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GNUPGHOME=gnupghome,
               LC_ALL="C")
    return env


def _gen_key(home, uid):
    subprocess.run(["gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "",
                    "--quick-gen-key", uid, "ed25519", "sign", "never"],
                   env={**os.environ, "GNUPGHOME": home}, check=True, capture_output=True)
    out = subprocess.run(["gpg", "--batch", "--with-colons", "--list-secret-keys", uid],
                         env={**os.environ, "GNUPGHOME": home}, check=True,
                         capture_output=True).stdout.decode()
    return next(l.split(":")[9] for l in out.splitlines() if l.startswith("fpr:"))


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ktmp = tempfile.mkdtemp(prefix="se488k")
        cls.gh = os.path.join(cls.ktmp, "g")
        os.makedirs(cls.gh, mode=0o700)
        cls.fpr = _gen_key(cls.gh, "Fixture WebFlow <webflow@fixture.invalid>")
        cls.fpr_otra = _gen_key(cls.gh, "Otra Clave <otra@fixture.invalid>")
        cls.clave = os.path.join(cls.ktmp, "webflow.asc")
        with open(cls.clave, "wb") as f:
            f.write(subprocess.run(["gpg", "--batch", "--armor", "--export", cls.fpr],
                                   env={**os.environ, "GNUPGHOME": cls.gh}, check=True,
                                   capture_output=True).stdout)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(["gpgconf", "--homedir", cls.gh, "--kill", "all"], capture_output=True)
        shutil.rmtree(cls.ktmp, ignore_errors=True)

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="se488r")
        self.repo = os.path.join(self.tmp, "aprob")
        self.genesis = self.nuevo_repo(self.repo)
        self.n = 0
        self.pol = {"genesis": self.genesis, "rama": "main",
                    "autor": {"email": OPERADORA[1], "nombre": OPERADORA[0]},
                    "clave_webflow": self.clave, "huella_webflow": self.fpr,
                    "tipos": ["savia-merge", "yema-contrato", "savia-settings"],
                    "libro": os.path.join(self.tmp, "libro"), "caducidad_max_horas": 24}

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ------------------------------------------------------------ fixture git
    def git(self, *args, repo=None, autor=BOT, fecha=T0, check=True):
        env = _git_env(self.gh)
        t = fecha.strftime("%Y-%m-%dT%H:%M:%S+0000")
        env.update(GIT_AUTHOR_NAME=autor[0], GIT_AUTHOR_EMAIL=autor[1], GIT_AUTHOR_DATE=t,
                   GIT_COMMITTER_NAME="GitHub", GIT_COMMITTER_EMAIL="noreply@github.com",
                   GIT_COMMITTER_DATE=t)
        p = subprocess.run(["git", "-c", "gpg.program=gpg", "-C", repo or self.repo, *args],
                           env=env, capture_output=True)
        if check and p.returncode != 0:
            raise AssertionError(p.stderr.decode())
        return p.stdout.decode().strip()

    def nuevo_repo(self, ruta):
        os.makedirs(ruta)
        self.git("init", "-q", "-b", "main", repo=ruta)
        with open(os.path.join(ruta, "README.md"), "w") as f:
            f.write(f"repo {os.path.basename(ruta)}\n")  # génesis distinto por repo
        self.git("add", "-A", repo=ruta)
        self.git("commit", "-q", "-m", "génesis", repo=ruta, fecha=T0 - 48 * H)
        return self.git("rev-parse", "HEAD", repo=ruta)

    def escribir(self, ruta, contenido, repo=None):
        p = os.path.join(repo or self.repo, ruta)
        os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
        with open(p, "wb") as f:
            f.write(contenido if isinstance(contenido, bytes) else contenido.encode())

    def rama(self, cambios, repo=None, base="main"):
        """Rama de la App con un commit (sin firmar) que aplica `cambios(repo)`."""
        repo = repo or self.repo
        self.n += 1
        nombre = f"pr{self.n}"
        self.git("checkout", "-q", "-b", nombre, base, repo=repo)
        cambios(repo)
        self.git("add", "-A", repo=repo)
        self.git("commit", "-q", "-m", f"aprobación {self.n}", repo=repo)
        self.git("checkout", "-q", "main", repo=repo)
        return nombre

    def fusionar(self, ramas, firma="good", autor=OPERADORA, fecha=T0 + H, repo=None):
        args = ["merge", "--no-ff", "-q", "-m", "Merge pull request"]
        if firma == "good":
            args = ["-c", f"user.signingkey={self.fpr}"] + args + ["-S"]
        elif firma == "otra":
            args = ["-c", f"user.signingkey={self.fpr_otra}"] + args + ["-S"]
        self.git(*args, *ramas, repo=repo, autor=autor, fecha=fecha)
        return self.git("rev-parse", "HEAD", repo=repo)

    def aprobar(self, tipo="savia-merge", objeto=None, repo=None, **kw):
        """Artefacto válido + PR + merge firmado. Devuelve (M, ruta, artefacto)."""
        ruta, art = self.artefacto(tipo, objeto)
        r = self.rama(lambda d: self.escribir(ruta, json.dumps(art), d), repo=repo)
        return self.fusionar([r], repo=repo, **kw), ruta, art

    def artefacto(self, tipo="savia-merge", objeto=None, horas=24):
        objeto = objeto or {"repo": REPO, "prs": [{"numero": 7, "head_sha": SHA_A}]}
        return ar.nuevo_artefacto(tipo, objeto, T0, horas)

    def verif(self, m, esperado=None, tipo="savia-merge", ahora=T0 + 2 * H, consumir=False, **kw):
        esperado = esperado or {"repo": REPO, "numero": 7, "head_sha": SHA_A}
        return ar.verificar(self.pol, self.repo, m, tipo, esperado, ahora, consumir=consumir, **kw)

    def assertRechazo(self, r, codigo, condicion):
        self.assertEqual(r["codigo"], codigo, r)
        self.assertEqual(r["condicion"], condicion, r)


class R1Artefacto(Base):
    def test_resumen_determinista_y_nuevo_valido(self):
        ruta, art = self.artefacto()
        self.assertEqual(art["resumen"], ar.generar_resumen("savia-merge", art["objeto"]))
        self.assertRegex(ruta, r"^aprobaciones/savia-merge/20261110-pr-7-[0-9a-f]{8}\.json$")
        self.assertEqual(ar.validar_artefacto(art, ruta), (T0, T0 + 24 * H))

    def test_lista_blanca_de_ruta(self):
        ruta, art = self.artefacto()
        n8 = art["nonce"][:8]
        for mala in (f"aprobaciones/savia-merge/20261110-pr/7-{n8}.json",
                     f"aprobaciones/savia-merge/../20261110-pr-7-{n8}.json",
                     f"aprobaciones/savia-merge/20261110-pr-7..-{n8}.json",
                     f"aprobaciones/savia-merge/20261110-pr-7ñ-{n8}.json",
                     f"aprobaciones/otro-tipo/20261110-pr-7-{n8}.json",
                     f"aprobaciones/savia-merge/2026111-pr-7-{n8}.json",
                     ruta + "\n"):
            with self.subTest(ruta=mala), self.assertRaises(ar.Rechazo) as cm:
                ar.validar_artefacto(art, mala)
            self.assertEqual(cm.exception.condicion, "R2.5")

    def test_ruta_no_casa_con_tipo_id_nonce_o_fecha(self):
        ruta, art = self.artefacto()
        n8 = art["nonce"][:8]
        otro8 = "0" * 8 if n8 != "0" * 8 else "1" * 8
        for mala in (f"aprobaciones/yema-contrato/20261110-pr-7-{n8}.json",
                     f"aprobaciones/savia-merge/20261110-pr-8-{n8}.json",
                     f"aprobaciones/savia-merge/20261110-pr-7-{otro8}.json",
                     f"aprobaciones/savia-merge/20261111-pr-7-{n8}.json"):
            with self.subTest(ruta=mala), self.assertRaises(ar.Rechazo) as cm:
                ar.validar_artefacto(art, mala)
            self.assertEqual(cm.exception.condicion, "R2.5")
        self.assertEqual(ar.validar_artefacto(art, ruta)[0], T0)

    def test_esquema_y_nonce_invalidos(self):
        ruta, art = self.artefacto()
        casos = {"nonce corto": {**art, "nonce": art["nonce"][:15]},
                 "nonce mayúsculas": {**art, "nonce": art["nonce"].upper()},
                 "nonce con salto": {**art, "nonce": art["nonce"] + "\n"},
                 "fecha con salto": {**art, "emitida": art["emitida"] + "\n"},
                 "clave extra": {**art, "extra": 1},
                 "sin resumen": {k: v for k, v in art.items() if k != "resumen"},
                 "esquema": {**art, "esquema": "aprobacion/2"},
                 "fecha local": {**art, "emitida": "2026-11-10T10:00:00+01:00"}}
        for nombre, a in casos.items():
            with self.subTest(nombre), self.assertRaises(ar.Rechazo) as cm:
                ar.validar_artefacto(a, ruta)
            self.assertEqual(cm.exception.codigo, ar.INVALIDO)

    def test_ventana_mayor_de_24h_rechazada_aunque_la_politica_diga_mas(self):
        ruta, art = self.artefacto()
        a = {**art, "caduca": ar.fmt_fecha(T0 + 24 * H + dt.timedelta(seconds=1))}
        with self.assertRaises(ar.Rechazo) as cm:
            ar.validar_artefacto(a, ruta, max_horas=24 * 365)
        self.assertEqual(cm.exception.condicion, "R2.6")
        a = {**art, "caduca": ar.fmt_fecha(T0 + 24 * H)}  # límite exacto: vale
        self.assertEqual(ar.validar_artefacto(a, ruta, max_horas=24 * 365)[1], T0 + 24 * H)

    def test_resumen_que_no_coincide(self):
        ruta, art = self.artefacto()
        with self.assertRaises(ar.Rechazo) as cm:
            ar.validar_artefacto({**art, "resumen": art["resumen"] + " "}, ruta)
        self.assertEqual(cm.exception.condicion, "R1")

    def test_objetos_mal_formados(self):
        malos = [("yema-contrato", {"id": "c1", "huella": "ab" * 16}),
                 ("yema-contrato", {"id": "C1", "huella": "a" * 64}),
                 ("yema-contrato", {"id": "c1\n", "huella": "a" * 64}),
                 ("yema-contrato", {"id": "c1", "huella": "a" * 64 + "\n"}),
                 ("savia-merge", {"repo": REPO + "\n", "prs": [{"numero": 1, "head_sha": SHA_A}]}),
                 ("savia-merge", {"repo": "org/savia", "prs": []}),
                 ("savia-merge", {"repo": "org/..", "prs": [{"numero": 1, "head_sha": SHA_A}]}),
                 ("savia-merge", {"repo": REPO, "prs": [{"numero": 1, "head_sha": SHA_A[:12]}]}),
                 ("savia-merge", {"repo": REPO, "prs": [{"numero": True, "head_sha": SHA_A}]}),
                 ("savia-settings", {"fichero": "../x", "sha256_antes": "a" * 64,
                                     "sha256_despues": "b" * 64, "diff": ""}),
                 ("otro", {})]
        for tipo, obj in malos:
            with self.subTest(tipo=tipo, obj=obj), self.assertRaises(ar.Rechazo):
                ar.validar_objeto(tipo, obj)

    def test_cli_nuevo_y_artefacto(self):
        obj = json.dumps({"id": "contrato-1", "huella": "c" * 64})
        p = subprocess.run([sys.executable, SCRIPT, "nuevo", "--tipo", "yema-contrato",
                            "--objeto", obj, "--horas", "2"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        d = json.loads(p.stdout)
        f = os.path.join(self.tmp, "a.json")
        with open(f, "w") as fh:
            json.dump(d["artefacto"], fh)
        ok = subprocess.run([sys.executable, SCRIPT, "artefacto", f, "--ruta", d["ruta"]],
                            capture_output=True)
        self.assertEqual(ok.returncode, 0)
        malo = subprocess.run([sys.executable, SCRIPT, "artefacto", f, "--ruta",
                               d["ruta"].replace("contrato-1", "contrato-2")], capture_output=True)
        self.assertEqual(malo.returncode, 2)
        p = subprocess.run([sys.executable, SCRIPT, "nuevo", "--tipo", "yema-contrato",
                            "--objeto", obj, "--horas", "25"], capture_output=True)
        self.assertEqual(p.returncode, 2)


class R2Recibo(Base):
    def test_acepta_merge_valido(self):
        m, _, art = self.aprobar()
        r = self.verif(m)
        self.assertEqual(r["codigo"], 0, r)
        self.assertEqual(r["unidad"], f"{REPO}#7")
        self.assertEqual(r["via"], f"github:{m[:12]}")
        self.assertFalse(r["consumido"])

    def test_sin_firma(self):
        m, _, _ = self.aprobar(firma=None)
        self.assertRechazo(self.verif(m), 2, "R2.3")

    def test_firma_de_otra_clave(self):
        m, _, _ = self.aprobar(firma="otra")
        self.assertRechazo(self.verif(m), 2, "R2.3")

    def test_config_del_espejo_no_redirige_gpg(self):
        falso = os.path.join(self.tmp, "gpg-falso")
        with open(falso, "w") as f:
            # git pasa --status-fd=1: el falso escribe en stdout un GOODSIG de la clave fijada.
            f.write("#!/bin/sh\ncat >/dev/null\necho '[GNUPG:] NEWSIG'\necho '[GNUPG:] GOODSIG X Y'\n"
                    f"echo '[GNUPG:] VALIDSIG {self.fpr} 2026-11-10 0 4 0 22 8 00 {self.fpr}'\n"
                    "echo '[GNUPG:] TRUST_ULTIMATE 0 pgp'\nexit 0\n")
        os.chmod(falso, 0o755)
        m, _, _ = self.aprobar(firma="otra")
        self.git("config", "gpg.program", falso)
        self.git("config", "gpg.openpgp.program", falso)
        self.assertRechazo(self.verif(m), 2, "R2.3")

    # ---- P1 de la revisión de seguridad: el espejo no puede alterar lo que se lee.
    def _artefacto_falso(self, art):
        """Mismo tipo, ruta, id y nonce; otra cabeza. Devuelve el oid del blob falso."""
        obj = {"repo": REPO, "prs": [{"numero": 7, "head_sha": SHA_B}]}
        falso = {**art, "objeto": obj, "resumen": ar.generar_resumen("savia-merge", obj)}
        f = os.path.join(self.tmp, "falso.json")
        with open(f, "w") as fh:
            fh.write(json.dumps(falso))
        return self.git("hash-object", "-w", f)

    def _blob_de(self, m, ruta):
        return self.git("rev-parse", f"{m}:{ruta}")

    ESPERADO_B = {"repo": REPO, "numero": 7, "head_sha": SHA_B}

    def test_refs_replace_no_cambia_el_artefacto(self):
        m, ruta, art = self.aprobar()
        self.git("replace", self._blob_de(m, ruta), self._artefacto_falso(art))
        r = self.verif(m, self.ESPERADO_B)
        self.assertRechazo(r, 2, "espejo")
        self.assertIn("replace", r["motivo"])

    def test_replace_ignorado_aunque_no_se_vea_la_ref(self):
        # Defensa en profundidad: aunque la ref de reemplazo se esconda bajo otro
        # namespace (GIT_REPLACE_REF_BASE del atacante no llega: el env se limpia),
        # git no debe aplicar reemplazos al leer.
        m, ruta, art = self.aprobar()
        self.git("replace", self._blob_de(m, ruta), self._artefacto_falso(art))
        esp = ar.Espejo(self.repo)
        self.assertEqual(esp.out("rev-parse", f"{m}:{ruta}"), self._blob_de(m, ruta) + "\n")
        contenido = esp.run("cat-file", "blob", self._blob_de(m, ruta)).stdout
        self.assertEqual(json.loads(contenido)["objeto"]["prs"][0]["head_sha"], SHA_A)

    def test_grafts_no_ocultan_un_commit_sin_firmar(self):
        m1, _, _ = self.aprobar()
        self.git("commit", "-q", "--allow-empty", "-m", "suelto", fecha=T0 + 90 * dt.timedelta(minutes=1))
        x = self.git("rev-parse", "HEAD")
        ruta, art = self.artefacto(objeto={"repo": REPO, "prs": [{"numero": 9, "head_sha": SHA_A}]})
        m2 = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(art), d))],
                           fecha=T0 + 2 * H)
        self.assertEqual(self.git("rev-parse", f"{m2}^1"), x)
        os.makedirs(os.path.join(self.repo, ".git", "info"), exist_ok=True)
        with open(os.path.join(self.repo, ".git", "info", "grafts"), "w") as f:
            f.write(f"{m2} {m1} {self.git('rev-parse', f'{m2}^2')}\n")
        r = self.verif(m1, ahora=T0 + 3 * H)
        self.assertRechazo(r, 2, "espejo")
        self.assertIn("grafts", r["motivo"])
        # Sin el fichero de grafts, el commit suelto se ve y se rechaza por R2.2.
        os.remove(os.path.join(self.repo, ".git", "info", "grafts"))
        self.assertRechazo(self.verif(m1, ahora=T0 + 3 * H), 2, "R2.2")

    def test_shallow_rechazado(self):
        m, _, _ = self.aprobar()
        with open(os.path.join(self.repo, ".git", "shallow"), "w") as f:
            f.write(self.git("rev-parse", f"{m}^1") + "\n")
        r = self.verif(m)
        self.assertRechazo(r, 2, "espejo")
        self.assertIn("shallow", r["motivo"])

    def test_objeto_suelto_falsificado(self):
        import zlib
        m, ruta, art = self.aprobar()
        blob = self._blob_de(m, ruta)
        obj = {"repo": REPO, "prs": [{"numero": 7, "head_sha": SHA_B}]}
        falso = json.dumps({**art, "objeto": obj,
                            "resumen": ar.generar_resumen("savia-merge", obj)}).encode()
        p = os.path.join(self.repo, ".git", "objects", blob[:2], blob[2:])
        os.chmod(p, 0o644)
        with open(p, "wb") as f:
            f.write(zlib.compress(b"blob %d\0" % len(falso) + falso))
        r = self.verif(m, self.ESPERADO_B)
        self.assertEqual(r["codigo"], 2, r)
        self.assertEqual(r["condicion"], "espejo", r)

    def test_arbol_suelto_falsificado(self):
        """El árbol de M apunta a un blob falso con su propio hash correcto: la
        comprobación del hash del blob no basta; la detecta fsck."""
        m, ruta, art = self.aprobar()
        blob_falso = self._artefacto_falso(art)
        env = {**_git_env(self.gh), "GIT_INDEX_FILE": os.path.join(self.tmp, "idx")}

        def g(*a):
            return subprocess.run(["git", "-C", self.repo, *a], env=env, check=True,
                                  capture_output=True).stdout.decode().strip()
        g("read-tree", m)
        g("update-index", "--cacheinfo", f"100644,{blob_falso},{ruta}")
        arbol_falso, arbol = g("write-tree"), g("rev-parse", f"{m}^{{tree}}")
        obj = os.path.join(self.repo, ".git", "objects")
        destino = os.path.join(obj, arbol[:2], arbol[2:])
        os.chmod(destino, 0o644)
        shutil.copyfile(os.path.join(obj, arbol_falso[:2], arbol_falso[2:]), destino)
        r = self.verif(m, self.ESPERADO_B)
        self.assertRechazo(r, 2, "espejo")
        self.assertIn("fsck", r["motivo"])

    def test_autor_bot(self):
        m, _, _ = self.aprobar(autor=BOT)
        self.assertRechazo(self.verif(m), 2, "R2.4")

    def test_un_solo_padre(self):
        ruta, art = self.artefacto()
        self.escribir(ruta, json.dumps(art))
        self.git("add", "-A")
        self.git("-c", f"user.signingkey={self.fpr}", "commit", "-q", "-S", "-m", "directo",
                 autor=OPERADORA, fecha=T0 + H)
        self.assertRechazo(self.verif(self.git("rev-parse", "HEAD")), 2, "R2.2")

    def test_octopus(self):
        ruta, art = self.artefacto()
        r1 = self.rama(lambda d: self.escribir(ruta, json.dumps(art), d))
        r2 = self.rama(lambda d: self.escribir("otro.txt", "x", d))
        m = self.fusionar([r1, r2])
        self.assertRechazo(self.verif(m), 2, "R2.2")

    def test_dos_ficheros(self):
        ruta, art = self.artefacto()

        def cambios(d):
            self.escribir(ruta, json.dumps(art), d)
            self.escribir("aprobaciones/savia-merge/extra.json", "{}", d)
        m = self.fusionar([self.rama(cambios)])
        self.assertRechazo(self.verif(m), 2, "R2.5")

    def test_entrada_m_modifica_existente(self):
        m1, ruta, art = self.aprobar()
        self.assertEqual(self.verif(m1)["codigo"], 0)
        art2 = {**art, "resumen": art["resumen"]}
        m2 = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(art2, indent=1), d))],
                           fecha=T0 + 90 * dt.timedelta(minutes=1))
        r = self.verif(m2)
        self.assertRechazo(r, 2, "R2.5")
        self.assertIn("alta", r["motivo"])

    def test_borrado_renombrado_y_cambio_de_modo(self):
        m1, ruta, art = self.aprobar()
        nueva_ruta, _ = self.artefacto()
        casos = {"borrado": lambda d: os.remove(os.path.join(d, ruta)),
                 "renombrado": lambda d: os.rename(os.path.join(d, ruta), os.path.join(d, nueva_ruta)),
                 "modo": lambda d: os.chmod(os.path.join(d, ruta), 0o755)}
        for nombre, cambio in casos.items():
            with self.subTest(nombre):
                self.git("reset", "-q", "--hard", m1)
                m = self.fusionar([self.rama(cambio)], fecha=T0 + 90 * dt.timedelta(minutes=1))
                self.assertRechazo(self.verif(m), 2, "R2.5")

    def test_alta_ejecutable_rechazada(self):
        ruta, art = self.artefacto()

        def cambios(d):
            self.escribir(ruta, json.dumps(art), d)
            os.chmod(os.path.join(d, ruta), 0o755)
        m = self.fusionar([self.rama(cambios)])
        self.assertRechazo(self.verif(m), 2, "R2.5")

    def test_ruta_fuera_de_lista_blanca_en_el_merge(self):
        _, art = self.artefacto()
        ruta = f"aprobaciones/savia-merge/20261110-pr-7ñ-{art['nonce'][:8]}.json"
        m = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(art), d))])
        self.assertRechazo(self.verif(m), 2, "R2.5")

    def test_ruta_que_no_casa_con_el_nonce_en_el_merge(self):
        ruta, art = self.artefacto()
        otro = {**art, "nonce": ("0" * 16 if art["nonce"][0] != "0" else "1" * 16)}
        m = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(otro), d))])
        self.assertRechazo(self.verif(m), 2, "R2.5")

    def test_esquema_invalido_en_el_merge(self):
        ruta, art = self.artefacto()
        m = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps({**art, "nonce": "zz"}), d))])
        self.assertRechazo(self.verif(m), 2, "R2.6")

    def test_ventana_inflada_en_el_merge(self):
        ruta, art = self.artefacto()
        a = {**art, "caduca": ar.fmt_fecha(T0 + 24 * 365 * H)}
        m = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(a), d))])
        self.pol["caducidad_max_horas"] = 24 * 365
        self.assertRechazo(self.verif(m), 2, "R2.6")

    def test_resumen_manipulado_en_el_merge(self):
        ruta, art = self.artefacto()
        a = {**art, "resumen": "Fusionar una PR inofensiva."}
        m = self.fusionar([self.rama(lambda d: self.escribir(ruta, json.dumps(a), d))])
        self.assertRechazo(self.verif(m), 2, "R1")

    def test_fuera_de_la_cadena_first_parent(self):
        self.git("branch", "lateral", "main")
        ruta, art = self.artefacto()
        r = self.rama(lambda d: self.escribir(ruta, json.dumps(art), d))
        self.git("checkout", "-q", "lateral")
        self.git("-c", f"user.signingkey={self.fpr}", "merge", "--no-ff", "-q", "-S", "-m", "x", r,
                 autor=OPERADORA, fecha=T0 + H)
        m = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "main")
        self.assertRechazo(self.verif(m), 2, "R2.1")

    def test_trasplante_desde_otro_repo(self):
        otro = os.path.join(self.tmp, "savia")
        self.nuevo_repo(otro)
        m, _, _ = self.aprobar(repo=otro)
        self.git("fetch", "-q", otro, "main")
        self.git("update-ref", "refs/heads/main", m)
        self.git("reset", "-q", "--hard", m)
        r = self.verif(m)
        self.assertRechazo(r, 2, "R2.1")
        self.assertIn("génesis", r["motivo"])

    def test_commit_intermedio_no_aprobado(self):
        m1, _, _ = self.aprobar()
        self.escribir("suelto.txt", "x")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "commit suelto", fecha=T0 + 90 * dt.timedelta(minutes=1))
        self.assertRechazo(self.verif(m1), 2, "R2.2")

    def test_espejo_reescrito_no_fast_forward(self):
        m1, _, _ = self.aprobar()
        self.assertEqual(self.verif(m1)["codigo"], 0)
        self.git("reset", "-q", "--hard", self.genesis)
        m2, _, _ = self.aprobar(fecha=T0 + 90 * dt.timedelta(minutes=1))
        r = self.verif(m2)
        self.assertRechazo(r, 2, "R2.1")
        self.assertIn("reescribió", r["motivo"])

    def test_tipo_no_habilitado(self):
        m, _, _ = self.aprobar()
        self.pol["tipos"] = ["yema-contrato"]
        self.assertRechazo(self.verif(m), 2, "R2.9")

    def test_otro_repo_y_pr_fuera_del_lote(self):
        m, _, _ = self.aprobar()
        self.assertRechazo(self.verif(m, {"repo": "org/otro", "numero": 7, "head_sha": SHA_A}), 2, "R2.6")
        self.assertRechazo(self.verif(m, {"repo": REPO, "numero": 8, "head_sha": SHA_A}), 2, "R2.6")

    def test_cabeza_distinta_es_no_vigente(self):
        m, _, _ = self.aprobar()
        self.assertRechazo(self.verif(m, {"repo": REPO, "numero": 7, "head_sha": SHA_B}), 1, "R2.6")

    def test_huella_distinta(self):
        obj = {"id": "contrato-1", "huella": "c" * 64}
        m, _, _ = self.aprobar("yema-contrato", obj)
        ok = self.verif(m, obj, tipo="yema-contrato")
        self.assertEqual(ok["codigo"], 0, ok)
        self.assertEqual(ok["unidad"], f"contrato-1@{'c' * 64}")
        r = self.verif(m, {"id": "contrato-1", "huella": "d" * 64}, tipo="yema-contrato")
        self.assertRechazo(r, 1, "R2.6")

    def test_caducado_y_limite(self):
        m, _, _ = self.aprobar()
        self.assertRechazo(self.verif(m, ahora=T0 + 24 * H), 1, "R2.7")
        self.assertEqual(self.verif(m, ahora=T0 + 24 * H - dt.timedelta(seconds=1))["codigo"], 0)

    def test_fecha_del_merge_fuera_de_la_ventana(self):
        m, _, _ = self.aprobar(fecha=T0 - H)
        r = self.verif(m)
        self.assertRechazo(r, 1, "R2.7")
        self.assertIn("fuera", r["motivo"])

    def test_ahora_anterior_al_suelo_monotono(self):
        m, _, _ = self.aprobar()
        # Por debajo de la fecha firmada del merge / punta.
        self.assertRechazo(self.verif(m, ahora=T0 + 30 * dt.timedelta(minutes=1)), 1, "R2.7")
        # Un 'ahora' aceptado al consumir sube el suelo; volver atrás no vale.
        lote = {"repo": REPO, "prs": [{"numero": 7, "head_sha": SHA_A}, {"numero": 8, "head_sha": SHA_B}]}
        self.git("reset", "-q", "--hard", self.genesis)
        shutil.rmtree(self.pol["libro"])
        m2, _, _ = self.aprobar(objeto=lote)
        self.assertEqual(self.verif(m2, ahora=T0 + 5 * H, consumir=True)["codigo"], 0)
        r = self.verif(m2, {"repo": REPO, "numero": 8, "head_sha": SHA_B}, ahora=T0 + 3 * H)
        self.assertRechazo(r, 1, "R2.7")
        self.assertEqual(self.verif(m2, {"repo": REPO, "numero": 8, "head_sha": SHA_B},
                                    ahora=T0 + 5 * H)["codigo"], 0)

    def test_ya_consumido(self):
        m, _, _ = self.aprobar()
        self.assertEqual(self.verif(m, consumir=True)["codigo"], 0)
        self.assertRechazo(self.verif(m), 1, "R2.8")

    def test_settings_valido_y_diff_falso(self):
        antes = b'{"a": 1}\n'
        despues = b'{"a": 2}\n'
        fichero = ".claude/settings.local.json"
        import hashlib
        obj = {"fichero": fichero, "sha256_antes": hashlib.sha256(antes).hexdigest(),
               "sha256_despues": hashlib.sha256(despues).hexdigest(),
               "diff": ar.diff_canonico(antes, despues, fichero)}
        m, _, _ = self.aprobar("savia-settings", obj)
        esp = {"fichero": fichero}
        r = self.verif(m, esp, tipo="savia-settings", contenidos=(antes, despues))
        self.assertEqual(r["codigo"], 0, r)
        self.assertRechazo(self.verif(m, esp, tipo="savia-settings"), 2, "R2.6")
        self.assertRechazo(self.verif(m, esp, tipo="savia-settings", contenidos=(b"{}\n", despues)), 1, "R2.6")
        # Diff que no lleva de antes a después (oculta un cambio extra).
        self.git("reset", "-q", "--hard", self.genesis)
        shutil.rmtree(self.pol["libro"])
        trampa = {**obj, "diff": ar.diff_canonico(antes, b'{"a": 3}\n', fichero)}
        m2, _, _ = self.aprobar("savia-settings", trampa)
        self.assertRechazo(self.verif(m2, esp, tipo="savia-settings", contenidos=(antes, despues)), 2, "R2.6")


class AC1bConsumo(Base):
    LOTE = {"repo": REPO, "prs": [{"numero": 7, "head_sha": SHA_A}, {"numero": 8, "head_sha": SHA_B}]}

    def test_lote_consumo_por_pr(self):
        m, _, _ = self.aprobar(objeto=self.LOTE)
        e7 = {"repo": REPO, "numero": 7, "head_sha": SHA_A}
        e8 = {"repo": REPO, "numero": 8, "head_sha": SHA_B}
        self.assertEqual(self.verif(m, e7, consumir=True)["codigo"], 0)
        self.assertEqual(self.verif(m, e8)["codigo"], 0)
        self.assertRechazo(self.verif(m, e7, consumir=True), 1, "R2.8")
        self.assertEqual(self.verif(m, e8, consumir=True)["codigo"], 0)

    def test_dos_procesos_concurrentes_pasa_uno(self):
        m, _, _ = self.aprobar()
        pol = os.path.join(self.tmp, "pol.json")
        with open(pol, "w") as f:
            json.dump(self.pol, f)
        cmd = [sys.executable, SCRIPT, "consumir", "--politica", pol, "--espejo", self.repo,
               "--commit", m, "--tipo", "savia-merge", "--ahora", ar.fmt_fecha(T0 + 2 * H),
               "--esperado", json.dumps({"repo": REPO, "numero": 7, "head_sha": SHA_A})]
        for _ in range(3):  # varias rondas: cada una con su libro limpio
            shutil.rmtree(self.pol["libro"], ignore_errors=True)
            procs = [subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                     for _ in range(4)]
            codigos = sorted(p.wait() for p in procs)
            self.assertEqual(codigos, [0, 1, 1, 1])
            with open(os.path.join(self.pol["libro"], "consumidos.jsonl")) as f:
                self.assertEqual(len(f.read().splitlines()), 1)

    def test_consumir_espera_al_cerrojo_exclusivo(self):
        """Determinista: espera a ver al hijo BLOQUEADO en flock (/proc/locks, marca '->')
        en vez de dormir un tiempo fijo. Sin flock el hijo nunca aparece como esperando."""
        import fcntl
        import time
        if not os.path.exists("/proc/locks"):
            self.fail("/proc/locks no disponible: este test exige Linux")
        m, _, _ = self.aprobar()
        pol = os.path.join(self.tmp, "pol.json")
        with open(pol, "w") as f:
            json.dump(self.pol, f)
        os.makedirs(self.pol["libro"], exist_ok=True)
        cerrojo = open(os.path.join(self.pol["libro"], ".cerrojo"), "a")
        fcntl.flock(cerrojo, fcntl.LOCK_EX)
        ino = os.fstat(cerrojo.fileno()).st_ino
        try:
            p = subprocess.Popen([sys.executable, SCRIPT, "consumir", "--politica", pol, "--espejo",
                                  self.repo, "--commit", m, "--tipo", "savia-merge", "--ahora",
                                  ar.fmt_fecha(T0 + 2 * H), "--esperado",
                                  json.dumps({"repo": REPO, "numero": 7, "head_sha": SHA_A})],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            limite = time.monotonic() + 60
            bloqueado = False
            while not bloqueado:
                self.assertIsNone(p.poll(), "consumir terminó sin esperar al cerrojo del libro")
                self.assertLess(time.monotonic(), limite, "el hijo no llegó a bloquearse")
                with open("/proc/locks") as f:
                    bloqueado = any("->" in l and f" {p.pid} " in l and f":{ino} " in l for l in f)
                time.sleep(0.02)
            self.assertFalse(os.path.exists(os.path.join(self.pol["libro"], "consumidos.jsonl")))
        finally:
            fcntl.flock(cerrojo, fcntl.LOCK_UN)
            cerrojo.close()
        self.assertEqual(p.wait(timeout=60), 0)

    def test_no_hay_devolucion_del_recibo_tras_consumir(self):
        m, _, _ = self.aprobar()
        self.assertEqual(self.verif(m, consumir=True)["codigo"], 0)
        # No se ejecuta ninguna acción aquí: el test solo fija que, una vez anotado, no hay
        # vía para «devolver» el recibo (ni verificar ni un segundo consumir lo aceptan).
        self.assertRechazo(self.verif(m), 1, "R2.8")
        self.assertRechazo(self.verif(m, consumir=True), 1, "R2.8")

    def test_libro_corrupto_es_invalido(self):
        m, _, _ = self.aprobar()
        os.makedirs(self.pol["libro"], exist_ok=True)
        with open(os.path.join(self.pol["libro"], "consumidos.jsonl"), "w") as f:
            f.write("no es json\n")
        self.assertRechazo(self.verif(m), 2, "R2.8")


class AC2FailClosed(Base):
    def test_sin_gpg(self):
        m, _, _ = self.aprobar()
        pol = os.path.join(self.tmp, "pol.json")
        with open(pol, "w") as f:
            json.dump(self.pol, f)
        binsolo = os.path.join(self.tmp, "bin")
        os.makedirs(binsolo)
        os.symlink(shutil.which("git"), os.path.join(binsolo, "git"))
        p = subprocess.run([sys.executable, SCRIPT, "verificar", "--politica", pol, "--espejo", self.repo,
                            "--commit", m, "--tipo", "savia-merge", "--ahora", ar.fmt_fecha(T0 + 2 * H),
                            "--esperado", json.dumps({"repo": REPO, "numero": 7, "head_sha": SHA_A})],
                           env={**os.environ, "PATH": binsolo}, capture_output=True, text=True)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        d = json.loads(p.stdout)
        self.assertEqual(d["condicion"], "entorno", d)
        self.assertIn("gpg", d["motivo"])

    def test_clave_fijada_ausente_o_sin_huella(self):
        m, _, _ = self.aprobar()
        for cambio, cond in ((("clave_webflow", "/no/existe.asc"), "R2.3"),
                             (("huella_webflow", ""), "R2.3"),
                             (("genesis", ""), "R2.1"),
                             (("autor", {}), "R2.4")):
            with self.subTest(cambio[0]):
                pol = dict(self.pol)
                pol[cambio[0]] = cambio[1]
                r = ar.verificar(pol, self.repo, m, "savia-merge",
                                 {"repo": REPO, "numero": 7, "head_sha": SHA_A}, T0 + 2 * H)
                self.assertRechazo(r, 2, cond)

    def test_clave_fijada_distinta_de_la_firmante(self):
        m, _, _ = self.aprobar()
        self.pol["huella_webflow"] = self.fpr_otra
        self.assertRechazo(self.verif(m), 2, "R2.3")

    def test_espejo_sin_rama(self):
        m, _, _ = self.aprobar()
        self.pol["rama"] = "no-existe"
        self.assertRechazo(self.verif(m), 2, "R2.1")

    def test_commit_y_rama_fuera_de_lista_blanca(self):
        m, _, _ = self.aprobar()
        for sha in (m[:12], m.upper(), m + "\n", "--output=/tmp/x", "main"):
            with self.subTest(sha=sha):
                self.assertRechazo(self.verif(sha), 2, "R2.1")
        for rama in ("-x", "main..x", "+main", "a:b", "main\n"):
            with self.subTest(rama=rama):
                self.pol["rama"] = rama
                r = self.verif(m)
                self.assertRechazo(r, 2, "R2.1")
                self.assertIn("lista blanca", r["motivo"])

    def test_sin_libro_configurado(self):
        m, _, _ = self.aprobar()
        del self.pol["libro"]
        self.assertRechazo(self.verif(m), 2, "R2.8")


class Sincronizar(Base):
    def test_solo_fast_forward(self):
        espejo = os.path.join(self.tmp, "espejo.git")
        subprocess.run(["git", "clone", "-q", "--bare", self.repo, espejo], check=True,
                       env=_git_env(self.gh))
        m1, _, _ = self.aprobar()
        ar.sincronizar(espejo, self.repo)
        self.assertEqual(self.git("rev-parse", "main", repo=espejo), m1)
        self.git("reset", "-q", "--hard", self.genesis)
        self.aprobar(fecha=T0 + 2 * H)
        with self.assertRaises(ar.Rechazo) as cm:
            ar.sincronizar(espejo, self.repo)
        self.assertEqual(cm.exception.condicion, "R2.1")
        self.assertEqual(self.git("rev-parse", "main", repo=espejo), m1)

    def test_remoto_y_rama_como_opciones_rechazados(self):
        espejo = os.path.join(self.tmp, "espejo.git")
        subprocess.run(["git", "clone", "-q", "--bare", self.repo, espejo], check=True,
                       env=_git_env(self.gh))
        marca = os.path.join(self.tmp, "ejecutado")
        for remoto, rama in ((f"--upload-pack=touch {marca};git-upload-pack", "main"),
                             (self.repo, "+main"), (self.repo, "main:otra"), (self.repo, "-main")):
            with self.subTest(remoto=remoto, rama=rama), self.assertRaises(ar.Rechazo) as cm:
                ar.sincronizar(espejo, remoto, rama)
            self.assertEqual(cm.exception.condicion, "R2.1")
        self.assertFalse(os.path.exists(marca))


if __name__ == "__main__":
    unittest.main()
