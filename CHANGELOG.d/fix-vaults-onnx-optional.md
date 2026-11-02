---
version_bump: patch
section: Fixed
---

### Fixed

- SaviaVaults (SE-489 M2): el reranker compila sin sus dependencias opcionales (onnxruntime-node, @huggingface/tokenizers); la CI omite la descarga CUDA de onnxruntime-node, que fallaba de forma intermitente y dejaba tsc en rojo en PRs ajenas a Vaults, y comprueba tsc con --omit=optional.

