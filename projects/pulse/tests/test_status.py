"""SE-532 S3: el estado derivado del catálogo en `pulse status` (sin datos / con deriva / sin deriva)."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

from pulse import catalogo, status  # noqa: E402
from test_catalogo import CatalogoBase, agente  # noqa: E402


class Estado(CatalogoBase):
    def test_sin_eventos_es_sin_datos_no_sin_deriva(self):
        d = status.collect(self.root)
        self.assertEqual(d["catalogo"]["estado"], "sin_datos")
        self.assertIn("sin datos", status.render(d))
        self.assertNotIn("sin deriva", status.render(d))

    def test_status_con_y_sin_deriva(self):
        self.escribir("beta", agente("beta", "editado"))
        catalogo.comprobar(self.root, self.repo)
        d = status.collect(self.root)
        self.assertEqual((d["catalogo"]["estado"], d["catalogo"]["agentes"]), ("con_deriva", ["beta"]))
        self.assertIn("Agentes desajustados con el repositorio: beta. Se resolverá al regenerar las copias.",
                      status.render(d))
        self.escribir("beta", agente("beta"))
        catalogo.comprobar(self.root, self.repo)
        d = status.collect(self.root)
        self.assertEqual(d["catalogo"]["estado"], "sin_deriva")
        self.assertIn("sin deriva", status.render(d))
        self.assertNotIn("desajustados", status.render(d))


if __name__ == "__main__":
    unittest.main()
