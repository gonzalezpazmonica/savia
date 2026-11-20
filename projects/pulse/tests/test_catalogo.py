"""SE-532 S3: aviso de deriva del catálogo de agentes en el ledger de Pulse.

Cada caso monta un repositorio mínimo con el conversor real y 3 agentes. Casos
negativos: catálogo idéntico no emite; el evento no lleva contenido; ledger
ilegible, conversor roto o catálogo vacío no dan «sin deriva».
"""
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REPO_REAL = os.path.dirname(os.path.dirname(PROJECT))
sys.path.insert(0, PROJECT)
sys.path.insert(0, HERE)

from pulse import catalogo, events, schema  # noqa: E402
from pulse.store import EntradaInvalida, PulseError  # noqa: E402
from test_pulse import Base  # noqa: E402

MARCA_CONTENIDO = "MARCA-DE-CONTENIDO-DEL-AGENTE-12345"


def agente(nombre, extra=""):
    return ("---\nname: %s\ndescription: agente de prueba\ntools: [Read, Bash]\ncolor: blue\n---\n"
            "Cuerpo %s %s\n" % (nombre, MARCA_CONTENIDO, extra))


class CatalogoBase(Base):
    def setUp(self):
        super().setUp()
        self.repo = os.path.join(self._tmp.name, "repo")
        os.makedirs(os.path.join(self.repo, "scripts"))
        os.makedirs(os.path.join(self.repo, ".claude", "agents"))
        os.makedirs(os.path.join(self.repo, ".opencode", "agents"))
        shutil.copy(os.path.join(REPO_REAL, "scripts", "agents-opencode-convert.sh"),
                    os.path.join(self.repo, "scripts", "agents-opencode-convert.sh"))
        for n in ("alfa", "beta", "gamma"):
            self.escribir(n, agente(n))
        self.regenerar()

    def escribir(self, nombre, texto, lado=".claude"):
        with open(os.path.join(self.repo, lado, "agents", nombre + ".md"), "w", encoding="utf-8") as fh:
            fh.write(texto)

    def regenerar(self):
        import subprocess
        env = dict(os.environ, SRC_DIR=os.path.join(self.repo, ".claude", "agents"),
                   DST_DIR=os.path.join(self.repo, ".opencode", "agents"), PROJECT_ROOT=self.repo)
        subprocess.run(["bash", os.path.join(self.repo, "scripts", "agents-opencode-convert.sh"), "--apply"],
                       env=env, check=True, capture_output=True)

    def eventos(self, *tipos):
        _, evs, _ = events.read_ledger(self.root)
        return [e for e in evs if e["tipo"] in (tipos or ("catalogo_deriva", "catalogo_resuelto"))]


class Huella(unittest.TestCase):
    def test_estable_y_sensible(self):
        a = catalogo.huella({"x": "h1", "y": "h2"})
        self.assertEqual(a, catalogo.huella({"y": "h2", "x": "h1"}))  # el orden no cuenta
        self.assertNotEqual(a, catalogo.huella({"x": "h1", "y": "h3"}))
        self.assertNotEqual(a, catalogo.huella({"x": "h1"}))
        self.assertRegex(a, r"^[0-9a-f]{16}$")

    def test_el_nombre_entra_en_la_huella(self):
        self.assertNotEqual(catalogo.huella({"x": "h"}), catalogo.huella({"y": "h"}))

    def test_ausente_no_es_vacio(self):
        self.assertNotEqual(catalogo.huella({"x": None}), catalogo.huella({"x": ""}))


class Deriva(CatalogoBase):
    def test_catalogo_identico_no_emite(self):
        self.assertEqual(catalogo.comprobar(self.root, self.repo), ("nada", None))
        self.assertEqual(catalogo.comprobar(self.root, self.repo), ("nada", None))
        self.assertEqual(self.eventos(), [])

    def test_cambiar_agente_sin_regenerar_emite_deriva(self):
        self.escribir("beta", agente("beta", "editado"))
        accion, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual(accion, "deriva")
        self.assertEqual(ev["agentes"], ["beta"])
        self.assertEqual(ev["motivo"], "espejo_distinto")
        self.assertEqual(ev["nivel"], "N1")
        self.assertNotEqual(ev["huella_repo"], ev["huella_vista"])
        self.assertEqual(len(self.eventos("catalogo_deriva")), 1)

    def test_misma_deriva_no_repite_evento(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        self.assertEqual(catalogo.comprobar(self.root, self.repo), ("nada", None))
        self.assertEqual(len(self.eventos()), 1)

    def test_deriva_que_cambia_de_agentes_emite_otra(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        self.escribir("gamma", agente("gamma", "editado"))
        accion, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual((accion, ev["agentes"]), ("deriva", ["beta", "gamma"]))

    def test_restaurar_emite_resolucion_y_estado_vuelve(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        self.escribir("beta", agente("beta"))
        accion, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual(accion, "resuelto")
        self.assertEqual(ev["tipo"], "catalogo_resuelto")
        self.assertEqual([e["tipo"] for e in self.eventos()], ["catalogo_deriva", "catalogo_resuelto"])
        self.assertEqual(catalogo.estado(events.read_ledger(self.root)[1])[0], "sin_deriva")
        self.assertEqual(catalogo.comprobar(self.root, self.repo), ("nada", None))  # sin segunda resolución

    def test_regenerar_tambien_resuelve(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        self.regenerar()
        self.assertEqual(catalogo.comprobar(self.root, self.repo)[0], "resuelto")

    def test_copia_editada_a_mano_es_deriva(self):
        self.escribir("alfa", agente("alfa", "a mano"), lado=".opencode")
        accion, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual((accion, ev["agentes"]), ("deriva", ["alfa"]))

    def test_copia_ausente(self):
        os.unlink(os.path.join(self.repo, ".opencode", "agents", "gamma.md"))
        accion, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual((accion, ev["agentes"], ev["motivo"]), ("deriva", ["gamma"], "espejo_ausente"))

    def test_ambos_motivos(self):
        os.unlink(os.path.join(self.repo, ".opencode", "agents", "gamma.md"))
        self.escribir("alfa", agente("alfa", "x"))
        _, ev = catalogo.comprobar(self.root, self.repo)
        self.assertEqual((ev["agentes"], ev["motivo"]), (["alfa", "gamma"], "ambos"))

    def test_agente_solo_en_opencode_no_cuenta(self):
        self.escribir("solo-oc", agente("solo-oc"), lado=".opencode")  # excepción de SE-253
        self.assertEqual(catalogo.comprobar(self.root, self.repo), ("nada", None))

    def test_evento_sin_contenido_de_agentes(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        self.escribir("beta", agente("beta"))
        catalogo.comprobar(self.root, self.repo)
        with open(os.path.join(self.root, events.EVENTS), encoding="utf-8") as fh:
            crudo = fh.read()
        self.assertNotIn(MARCA_CONTENIDO, crudo)
        self.assertNotIn("editado", crudo)
        for e in self.eventos():
            self.assertLessEqual(set(e) - {"agentes", "motivo", "huella_repo", "huella_vista", "huella"},
                                 {"schema_version", "id", "tipo", "at", "clase", "entrega", "nivel"})


class FalloCerrado(CatalogoBase):
    def test_nombre_fuera_del_patron_del_esquema_falla_con_mensaje(self):
        self.escribir("Mala.Nombre", agente("x"))
        with self.assertRaises(EntradaInvalida) as cm:
            catalogo.comprobar(self.root, self.repo)
        self.assertIn("Mala.Nombre", str(cm.exception))
        self.assertEqual(self.eventos(), [])

    def test_mas_de_200_desajustados_falla_cerrado(self):
        for i in range(catalogo.MAX_AGENTES + 1):
            self.escribir("a%03d" % i, agente("a%03d" % i))
        with self.assertRaises(EntradaInvalida) as cm:
            catalogo.comprobar(self.root, self.repo)
        self.assertIn("más de 200 agentes", str(cm.exception))
        self.assertEqual(self.eventos(), [])

    def test_catalogo_vacio_no_es_sin_deriva(self):
        for n in ("alfa", "beta", "gamma"):
            os.unlink(os.path.join(self.repo, ".claude", "agents", n + ".md"))
        with self.assertRaises(PulseError):
            catalogo.comprobar(self.root, self.repo)
        self.assertEqual(self.eventos(), [])

    def test_conversor_ausente(self):
        os.unlink(os.path.join(self.repo, "scripts", "agents-opencode-convert.sh"))
        with self.assertRaises(EntradaInvalida):
            catalogo.comprobar(self.root, self.repo)

    def test_conversor_roto_no_resuelve_una_deriva(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        with open(os.path.join(self.repo, "scripts", "agents-opencode-convert.sh"), "w") as fh:
            fh.write("#!/usr/bin/env bash\nexit 7\n")
        with self.assertRaises(PulseError):
            catalogo.comprobar(self.root, self.repo)
        self.assertEqual([e["tipo"] for e in self.eventos()], ["catalogo_deriva"])

    def test_ledger_ilegible_no_escribe(self):
        self.write(events.EVENTS, "", mode=0o666)  # escribible por otros: FALLIDA
        os.chmod(os.path.join(self.root, events.EVENTS), 0o666)
        self.escribir("beta", agente("beta", "editado"))
        with self.assertRaises(PulseError):
            catalogo.comprobar(self.root, self.repo)
        self.assertEqual(os.path.getsize(os.path.join(self.root, events.EVENTS)), 0)

    def test_repo_sin_directorio_de_agentes(self):
        with self.assertRaises(PulseError):
            catalogo.comprobar(self.root, os.path.join(self._tmp.name, "no-existe"))


class Contrato(unittest.TestCase):
    base = {"schema_version": "1", "id": "ev-0123456789abcdef", "at": "2026-11-15T10:00:00Z",
            "clase": "ninguna", "entrega": "ninguna", "nivel": "N1"}

    def errores(self, **campos):
        return schema.validate(dict(self.base, **campos), schema.load_schema("evento"))

    def deriva(self, **cambios):
        d = {"tipo": "catalogo_deriva", "agentes": ["alfa"], "huella_repo": "0" * 16,
             "huella_vista": "1" * 16, "motivo": "espejo_distinto"}
        d.update(cambios)
        return d

    def test_valido(self):
        self.assertEqual(self.errores(**self.deriva()), [])
        self.assertEqual(self.errores(tipo="catalogo_resuelto", huella="a" * 16), [])

    def test_sin_agentes_es_invalido(self):
        self.assertTrue(self.errores(**self.deriva(agentes=[])))

    def test_sin_motivo_o_motivo_libre_es_invalido(self):
        d = self.deriva()
        del d["motivo"]
        self.assertTrue(self.errores(**d))
        self.assertTrue(self.errores(**self.deriva(motivo="porque sí")))

    def test_nombre_con_ruta_o_contenido_es_invalido(self):
        self.assertTrue(self.errores(**self.deriva(agentes=["../etc/passwd"])))
        self.assertTrue(self.errores(**self.deriva(agentes=["Cuerpo del agente con espacios"])))

    def test_limite_de_agentes(self):
        self.assertEqual(self.errores(**self.deriva(agentes=["a%d" % i for i in range(200)])), [])
        self.assertTrue(self.errores(**self.deriva(agentes=["a%d" % i for i in range(201)])))

    def test_resuelto_sin_huella_invalido(self):
        self.assertTrue(self.errores(tipo="catalogo_resuelto"))


class Cli(CatalogoBase):
    def test_cli_deriva_y_resolucion(self):
        r = self.cli("catalogo", "--repo", self.repo)
        self.assertEqual((r.returncode, "Sin cambios" in r.stdout), (0, True), r.stderr)
        self.escribir("beta", agente("beta", "editado"))
        r = self.cli("catalogo", "--repo", self.repo)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("desajustados con el repositorio: beta", r.stdout)
        self.regenerar()
        r = self.cli("catalogo", "--repo", self.repo)
        self.assertIn("resuelta", r.stdout)

    def test_cli_repo_invalido_sale_distinto_de_cero(self):
        r = self.cli("catalogo", "--repo", os.path.join(self._tmp.name, "no-existe"))
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.eventos(), [])


if __name__ == "__main__":
    unittest.main()
