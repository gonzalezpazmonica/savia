"""Una fila 'Cableado' de docs/memory-architecture.md debe ser verificable:
la columna Consumidor da fichero:linea y esa linea nombra el script."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "memory-architecture.md"
REF = re.compile(r"^(\S+):(\d+)$")


def check(text, root):
    """Devuelve la lista de problemas de las filas Cableado."""
    problems, wired = [], 0
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 5 or not cells[4].startswith("Cableado"):
            continue
        wired += 1
        name, consumer = cells[2], cells[3]
        m = REF.match(consumer)
        if not m:
            problems.append(f"{name}: consumidor sin fichero:linea ({consumer})")
            continue
        f = root / m.group(1)
        lines = f.read_text(errors="replace").splitlines() if f.is_file() else []
        n = int(m.group(2))
        if not (1 <= n <= len(lines)) or name not in lines[n - 1]:
            problems.append(f"{name}: {consumer} no lo nombra")
    if wired == 0:
        problems.append("ninguna fila Cableado encontrada")
    return problems


def test_real_doc_wired_rows_verifiable():
    assert check(DOC.read_text(), ROOT) == []


def test_unwired_script_row_fails(tmp_path):
    (tmp_path / "a.sh").write_text("echo hola\n")
    row = "| X | canonico | huerfano.sh | a.sh:1 | Cableado |\n"
    assert check(row, tmp_path) != []


def test_row_without_line_ref_fails(tmp_path):
    row = "| X | canonico | huerfano.sh | CI | Cableado |\n"
    assert check(row, tmp_path) != []


def test_valid_row_passes(tmp_path):
    (tmp_path / "a.sh").write_text("bash scripts/ok.sh\n")
    row = "| X | canonico | ok.sh | a.sh:1 | Cableado |\n"
    assert check(row, tmp_path) == []


def test_out_of_range_line_fails(tmp_path):
    (tmp_path / "a.sh").write_text("ok.sh\n")
    row = "| X | canonico | ok.sh | a.sh:9 | Cableado |\n"
    assert check(row, tmp_path) != []


def test_sin_invocador_rows_not_checked(tmp_path):
    row = "| X | canonico | z.sh | ninguno | Sin invocador |\n"
    assert check(row, tmp_path) == ["ninguna fila Cableado encontrada"]
