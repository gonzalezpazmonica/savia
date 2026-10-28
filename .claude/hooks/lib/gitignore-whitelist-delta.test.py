#!/usr/bin/env python3
"""Tests de gitignore-whitelist-delta.py: evalúa el contenido RESULTANTE de .gitignore."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "gitignore-whitelist-delta.py")
# Nombres sintéticos; el prefijo se compone para no parecer una ruta real de proyecto.
WL = "!" + "pro" + "jects/"


def run(tool_input, gitignore=None, subdirs=()):
    with tempfile.TemporaryDirectory() as d:
        for sd in subdirs:
            os.makedirs(os.path.join(d, "pro" + "jects", sd), exist_ok=True)
            open(os.path.join(d, "pro" + "jects", sd, "dato.txt"), "w").close()
        if gitignore is not None:
            with open(os.path.join(d, ".gitignore"), "w") as fh:
                fh.write(gitignore)
        env = dict(os.environ, CLAUDE_PROJECT_DIR=d)
        p = subprocess.run([sys.executable, SCRIPT], input=json.dumps({"tool_input": tool_input}),
                           text=True, capture_output=True, env=env)
        return p.returncode


class Delta(unittest.TestCase):
    def test_otro_fichero_no_actua(self):
        self.assertEqual(run({"file_path": "docs/x.md", "old_string": "a", "new_string": WL + "a/"}), 0)

    def test_write_con_whitelist_nueva_bloquea(self):
        self.assertEqual(run({"file_path": ".gitignore", "content": "*.log\n" + WL + "a/\n"}, "*.log\n"), 1)

    def test_edicion_parcial_que_cambia_el_proyecto_bloquea(self):
        # Revisión de refutación: editar solo el nombre cambia qué proyecto se publica.
        self.assertEqual(run({"file_path": ".gitignore", "old_string": "alfa", "new_string": "beta"},
                             WL + "alfa/\n"), 1)

    def test_quitar_una_whitelist_no_bloquea(self):
        self.assertEqual(run({"file_path": ".gitignore", "old_string": WL + "c/\n", "new_string": ""},
                             "*.log\n" + WL + "c/\n"), 0)

    def test_editar_otra_linea_con_whitelist_existente_no_bloquea(self):
        self.assertEqual(run({"file_path": ".gitignore", "old_string": "*.log", "new_string": "*.tmp"},
                             "*.log\n" + WL + "d/\n"), 0)

    def test_multiedit_acumulado(self):
        self.assertEqual(run({"file_path": ".gitignore", "edits": [
            {"old_string": "*.log", "new_string": "*.log\n" + WL},
            {"old_string": WL, "new_string": WL + "e/"}]}, "*.log\n"), 1)

    def test_old_string_inexistente_evalua_el_texto_nuevo(self):
        self.assertEqual(run({"file_path": ".gitignore", "old_string": "no-existe",
                              "new_string": WL + "f/"}, "*.log\n"), 1)

    def test_entrada_no_evaluable_falla_cerrado(self):
        self.assertEqual(run({"file_path": ".gitignore", "old_string": None, "new_string": None}, ""), 2)

    def test_contenido_enorme_sin_sigpipe(self):
        self.assertEqual(run({"file_path": ".gitignore", "content": WL + "g/\n#" + "x" * 3000000}, ""), 1)


    def test_borrar_la_exclusion_general_bloquea(self):
        # Quitar la exclusión descubre proyectos privados sin añadir ninguna whitelist.
        self.assertEqual(run({"file_path": ".gitignore", "old_string": "pro" + "jects/*\n", "new_string": ""},
                             "pro" + "jects/*\n", subdirs=["alfa"]), 1)

    def test_whitelist_con_clase_de_caracteres_bloquea(self):
        self.assertEqual(run({"file_path": ".gitignore",
                              "content": "pro" + "jects/*\n![p]ro" + "jects/beta/\n"},
                             "pro" + "jects/*\n"), 1)

    def test_reordenar_sin_cambiar_lo_ignorado_no_bloquea(self):
        self.assertEqual(run({"file_path": ".gitignore", "content": "*.tmp\npro" + "jects/*\n"},
                             "pro" + "jects/*\n*.tmp\n", subdirs=["alfa"]), 0)

    def test_gitignore_anidado_con_excepcion_nueva_bloquea(self):
        # Un .gitignore dentro de la carpeta de proyectos puede reincluir lo que la raíz excluye.
        with tempfile.TemporaryDirectory() as d:
            sub = os.path.join(d, "pro" + "jects")
            os.makedirs(sub)
            env = dict(os.environ, CLAUDE_PROJECT_DIR=d)
            inp = json.dumps({"tool_input": {"file_path": os.path.join(sub, ".gitignore"), "content": "!*/\n"}})
            p = subprocess.run([sys.executable, SCRIPT], input=inp, text=True, capture_output=True, env=env)
            self.assertEqual(p.returncode, 1)

    def test_gitignore_anidado_sin_excepciones_no_bloquea(self):
        with tempfile.TemporaryDirectory() as d:
            sub = os.path.join(d, "docs")
            os.makedirs(sub)
            env = dict(os.environ, CLAUDE_PROJECT_DIR=d)
            inp = json.dumps({"tool_input": {"file_path": os.path.join(sub, ".gitignore"), "content": "*.tmp\n"}})
            p = subprocess.run([sys.executable, SCRIPT], input=inp, text=True, capture_output=True, env=env)
            self.assertEqual(p.returncode, 0)

if __name__ == "__main__":
    unittest.main()
