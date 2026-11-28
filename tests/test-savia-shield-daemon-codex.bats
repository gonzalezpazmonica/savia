#!/usr/bin/env bats
# SE-442, alertas #30-32: regresiones de confinamiento y autenticación.
# Ejercita el módulo real; sin daemon externo, NER, red ni token de la persona.
# Positivos: rutas internas y token correcto. Negativos: escape y acceso anónimo.

setup() {
  ROOT_CODEX="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

check_case() {
  run python3 -B - "$ROOT_CODEX" "$1" <<'PY'
import importlib.util
from contextlib import ExitStack
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest import mock

root, case = Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "shield_daemon_codex", root / "scripts/savia-shield-daemon.py"
)
daemon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(daemon)

with tempfile.TemporaryDirectory(prefix="shield-codex-") as temporary, ExitStack() as cleanup:
    cleanup.callback(os.chdir, root)
    base = Path(temporary)
    workspace = base / "workspace"
    outside = base / "workspace-sibling"
    (workspace / "docs").mkdir(parents=True)
    (workspace / "projects").mkdir()
    (outside / "docs").mkdir(parents=True)
    inside_file = workspace / "docs/existing.txt"
    outside_file = outside / "docs/existing.txt"
    inside_file.write_text("Server=synthetic-test", encoding="utf-8")
    outside_file.write_text("Contenido externo de prueba", encoding="utf-8")
    daemon.PROJ = str(workspace)
    daemon.ner = None
    os.chdir(workspace)

    # Auditoría de aperturas reales: detecta builtins.open y pathlib.Path.open.
    # Se registra después de crear/importar fixtures; no simula el confinamiento.
    opened = []
    tracking = {"active": True}
    cleanup.callback(tracking.update, active=False)

    def audit(event, args):
        if tracking["active"] and event == "open" and isinstance(args[0], (str, bytes, os.PathLike)):
            opened.append(os.path.realpath(os.fsdecode(args[0])))

    sys.addaudithook(audit)

    def gate(path, content="Contenido público de prueba", field="file_path"):
        return daemon.gate({"tool_input": {field: str(path), "content": content}})

    def reject_escape(path, field="file_path", content="Contenido público de prueba"):
        # Decisión de la operadora (2026-11-27): «No leer, no bloquear».
        # Fuera del workspace no se abre nada y se decide solo por el contenido
        # nuevo: el veredicto debe ser el mismo que el de ese contenido sobre
        # un fichero interno nuevo (sin nada previo que leer).
        result = gate(path, content, field)
        leaked = [p for p in opened if Path(p).is_relative_to(outside)]
        assert not leaked, f"Se abrió un fichero fuera del workspace: {leaked}; {result}"
        assert not any(e.get("type") == "split_write" for e in result.get("entities", [])), result
        reference = gate(workspace / "docs/reference-new.txt", content)
        assert result.get("verdict") == reference.get("verdict"), \
            f"La decisión depende de algo más que el contenido nuevo: {result} vs {reference}"
        assert result.get("verdict") == "ALLOW", f"Contenido público bloqueado: {result}"

    def post(configured, supplied):
        daemon.TOKEN = configured
        handler = daemon.H.__new__(daemon.H)
        body = json.dumps({"tool_input": {
            "file_path": str(workspace / "docs/new.txt"),
            "content": "Contenido público de prueba",
        }}).encode()
        handler.path = "/gate"
        handler.headers = {"Content-Length": str(len(body))}
        if supplied is not None:
            handler.headers["X-Shield-Token"] = supplied
        handler.rfile = io.BytesIO(body)
        handler._r = mock.Mock()
        handler._j = mock.Mock(wraps=handler._j)
        with mock.patch.object(daemon, "gate", wraps=daemon.gate) as dispatch:
            handler.do_POST()
        handler._r.assert_called_once()
        args = handler._r.call_args.args
        response, status = args[0], args[1] if len(args) > 1 else 200
        return status, response, dispatch, handler._j

    if case == "outside_absolute":
        reject_escape(outside_file)
    elif case == "outside_nonexistent":
        reject_escape(outside / "docs/missing.txt")
    elif case == "outside_private_pattern":
        # Una etiqueta privada no debe eludir el límite del workspace.
        reject_escape(outside / "config.local/missing.txt")
    elif case == "outside_trivial":
        reject_escape(outside_file, content="x")
    elif case == "symlink_file":
        link = workspace / "docs/link.txt"
        link.symlink_to(outside_file)
        reject_escape(link)
    elif case == "symlink_directory":
        link = workspace / "linked-docs"
        link.symlink_to(outside / "docs", target_is_directory=True)
        reject_escape(link / "existing.txt")
    elif case == "parent_escape":
        reject_escape("../workspace-sibling/docs/existing.txt")
    elif case == "absolute_parent_escape":
        reject_escape(str(workspace) + "/../workspace-sibling/docs/existing.txt")
    elif case == "path_alias_escape":
        reject_escape(outside_file, field="path")
    elif case == "outside_credential":
        # Caso propio (daemon2): fuera del workspace sigue bloqueando por contenido,
        # sin abrir el fichero externo existente.
        # Credencial cruzada completa en el contenido nuevo (sintética, nunca real).
        credential = "Ser" + "ver=db.synthetic;Pass" + "word=synthetic-value"
        result = gate(outside_file, credential)
        leaked = [p for p in opened if Path(p).is_relative_to(outside)]
        assert not leaked, f"Se abrió un fichero fuera del workspace: {leaked}; {result}"
        assert result.get("verdict") == "BLOCK", result
        assert any(e.get("type") == "connection_string" for e in result.get("entities", [])), result
    elif case == "relative_workspace":
        # El cwd del servicio no define el workspace: allí existe un señuelo.
        os.chdir(outside)
        result = gate("docs/existing.txt", "password=synthetic-value")
        assert str(outside_file) not in opened, f"Se leyó el cwd externo: {opened}"
        assert str(inside_file) in opened, f"No se leyó el fichero del workspace: {opened}"
        assert result.get("verdict") == "BLOCK", result
        assert any(e.get("type") == "split_write" for e in result.get("entities", [])), result
    elif case == "normalized_internal":
        # projects/../docs no es privado: debe escanear el destino canónico.
        credential = "AK" + "IA" + "0" * 16  # Credencial sintética, nunca real.
        result = gate(workspace / "projects/../docs/new.txt", credential)
        assert result.get("verdict") == "BLOCK", result
        assert any(e.get("type") == "aws_key" for e in result.get("entities", [])), result
    elif case == "absolute_internal":
        result = gate(inside_file)
        assert result.get("verdict") == "ALLOW", result
        assert str(inside_file) in opened, f"No se ejercitó la lectura interna: {opened}"
    elif case == "symlink_internal":
        link = workspace / "docs/internal-link.txt"
        link.symlink_to(inside_file)
        result = gate(link, "password=synthetic-value")
        assert result.get("verdict") == "BLOCK", result
        assert str(inside_file) in opened, opened
        assert any(e.get("type") == "split_write" for e in result.get("entities", [])), result
    elif case == "relative_internal":
        result = gate("docs/new.txt")
        assert result.get("verdict") == "ALLOW", result
    elif case == "new_internal":
        destination = workspace / "docs/new/deep.txt"
        assert not destination.exists()
        result = gate(destination)
        assert result.get("verdict") == "ALLOW", result
    elif case in {"no_config_no_header", "no_config_fake_header", "missing_header", "wrong_token"}:
        config, header = {
            "no_config_no_header": ("", None),
            "no_config_fake_header": ("", "synthetic-client-token"),
            "missing_header": ("synthetic-server-token", None),
            "wrong_token": ("synthetic-server-token", "synthetic-wrong-token"),
        }[case]
        status, response, dispatch, parse = post(config, header)
        dispatch.assert_not_called()
        parse.assert_not_called()
        assert status in {401, 403, 503}, (status, response)
        assert response.get("verdict") != "ALLOW", response
    elif case == "valid_token":
        status, response, dispatch, parse = post("synthetic-server-token", "synthetic-server-token")
        assert status == 200, (status, response)
        assert response.get("verdict") == "ALLOW", response
        dispatch.assert_called_once()
        parse.assert_called_once()
    else:
        raise AssertionError(f"Caso desconocido: {case}")
print("OK", case)
PY
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK $1" ]]
}

@test "codex: ruta absoluta externa no se abre y decide por contenido" {
  check_case outside_absolute
}
@test "codex: ruta externa inexistente (límite de prefijo workspace-sibling) decide por contenido" {
  check_case outside_nonexistent
}
@test "codex: destino privado externo no se abre y decide por contenido" {
  check_case outside_private_pattern
}
@test "codex: escape con contenido trivial no se abre y decide por contenido" {
  check_case outside_trivial
}
@test "codex: symlink de fichero que escapa no abre su destino y decide por contenido" {
  check_case symlink_file
}
@test "codex: symlink de directorio que escapa no abre su destino y decide por contenido" {
  check_case symlink_directory
}
@test "codex: escape relativo con .. no lee fuera y decide por contenido" {
  check_case parent_escape
}
@test "codex: ruta absoluta con .. que escapa no lee fuera y decide por contenido" {
  check_case absolute_parent_escape
}
@test "codex: escape mediante alias tool_input.path no lee fuera y decide por contenido" {
  check_case path_alias_escape
}
@test "codex: resuelve ruta relativa desde workspace aunque cwd sea externo" {
  check_case relative_workspace
}
@test "codex: normaliza .. interno antes de clasificar destino privado" {
  check_case normalized_internal
}
@test "codex: permite ruta absoluta interna y lee contenido existente" {
  check_case absolute_internal
}
@test "codex: conserva detección cross-write mediante symlink interno" {
  check_case symlink_internal
}
@test "codex: permite ruta relativa dentro del workspace" {
  check_case relative_internal
}
@test "codex: permite fichero nuevo en subdirectorio interno inexistente" {
  check_case new_internal
}
@test "codex: sin token configurado ni cabecera no procesa gate" {
  check_case no_config_no_header
}
@test "codex: sin token configurado una cabecera inventada no da acceso" {
  check_case no_config_fake_header
}
@test "codex: con token configurado rechaza cabecera ausente" {
  check_case missing_header
}
@test "codex: con token configurado rechaza token incorrecto" {
  check_case wrong_token
}
@test "codex: con token correcto procesa gate y permite contenido seguro" {
  check_case valid_token
}
@test "daemon2: credencial cruzada escrita fuera del workspace se bloquea por contenido" {
  check_case outside_credential
}
