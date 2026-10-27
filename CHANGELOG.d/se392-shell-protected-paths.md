---
version_bump: patch
section: Security
---

### Security

- SE-392 S3: escrituras a ficheros de gates desde bash (redirección, sed -i, borrado recursivo, git que reescribe el árbol) se deniegan con PROTECTED_GATE_PATH en Codex y OpenCode, con la misma decisión en ambos núcleos. También tras `cd`/`pushd`, con `git -C`, `bash -lc`, `sed -Ei`, heredoc a un shell, `find . -delete`, `git checkout -- .`, opciones con valor de los envoltorios, llaves y `$'\x..'`; lo no cubierto consta en tests/dual-cli/README.md.

