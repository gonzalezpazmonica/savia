'use strict';
// PR Guardian — exención de dependabot (Gate 1 y Gate 8).
//
// Decide si una PR queda exenta de las puertas de descripción y CHANGELOG.
// Solo lo está si se cumplen TODAS estas condiciones:
//   1. El autor es exactamente `dependabot[bot]` (github.event.pull_request.user.login).
//      El título no cuenta: nadie se exime escribiendo un nombre en él.
//   2. La PR toca al menos un fichero y todos son de dependencias:
//      - manifiestos o lockfiles conocidos (por nombre de fichero), o
//      - workflows de .github/workflows/ cuyo parche SOLO cambia líneas `uses:`
//        (la referencia de la acción y su comentario de versión).
//   3. Ante cualquier duda (parche ausente, fichero desconocido, estado
//      `removed`/`renamed`, entrada mal formada) la respuesta es NO exenta.
//
// Uso desde actions/github-script: require(<ruta>).evaluate(login, files)
// donde files es la salida de pulls.listFiles ({filename, status, patch}).
// Uso CLI (tests): node pr-guardian-dependabot-exempt.js <login> <files.json>

const DEPENDABOT_LOGIN = 'dependabot[bot]';

const DEPENDENCY_FILES = new Set([
  'package.json', 'package-lock.json', 'npm-shrinkwrap.json', 'yarn.lock',
  'pnpm-lock.yaml', 'requirements.txt', 'requirements-dev.txt',
  'pyproject.toml', 'poetry.lock', 'uv.lock', 'Pipfile', 'Pipfile.lock',
  'Cargo.toml', 'Cargo.lock', 'go.mod', 'go.sum', 'Gemfile', 'Gemfile.lock',
  'composer.json', 'composer.lock', 'pom.xml', 'build.gradle',
  'build.gradle.kts', 'gradle.properties', 'libs.versions.toml',
  'packages.lock.json', 'Directory.Packages.props',
]);

const WORKFLOW_RE = /^\.github\/workflows\/[^/]+\.ya?ml$/;
// Línea `uses:` de un paso, con comentario de versión opcional.
const USES_LINE_RE = /^\s*(-\s+)?uses:\s+[A-Za-z0-9._\/-]+@[A-Za-z0-9._\/-]+(\s+#.*)?$/;

function basename(path) {
  const parts = path.split('/');
  return parts[parts.length - 1];
}

// true solo si el parche existe y cada línea cambiada es una línea `uses:`.
function workflowPatchOnlyBumpsActions(patch) {
  if (typeof patch !== 'string' || patch.length === 0) return false;
  let changed = 0;
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@') || line.startsWith('\\')) continue;
    if (line.startsWith('+') || line.startsWith('-')) {
      if (!USES_LINE_RE.test(line.slice(1))) return false;
      changed += 1;
    }
  }
  return changed > 0;
}

function classifyFile(file) {
  if (!file || typeof file.filename !== 'string') return 'invalid entry';
  if (file.status && file.status !== 'modified') {
    return `${file.filename}: status ${file.status} (solo se admite modified)`;
  }
  if (DEPENDENCY_FILES.has(basename(file.filename))) return null;
  if (WORKFLOW_RE.test(file.filename)) {
    return workflowPatchOnlyBumpsActions(file.patch)
      ? null
      : `${file.filename}: el parche cambia algo más que líneas uses:`;
  }
  return `${file.filename}: no es un fichero de dependencias`;
}

function evaluate(login, files) {
  if (login !== DEPENDABOT_LOGIN) {
    return { exempt: false, reason: `autor ${login || '(vacío)'} no es ${DEPENDABOT_LOGIN}` };
  }
  if (!Array.isArray(files) || files.length === 0) {
    return { exempt: false, reason: 'lista de ficheros vacía o inválida' };
  }
  for (const f of files) {
    const problem = classifyFile(f);
    if (problem) return { exempt: false, reason: problem };
  }
  return { exempt: true, reason: `${files.length} fichero(s) de dependencias, autor ${DEPENDABOT_LOGIN}` };
}

module.exports = { evaluate, workflowPatchOnlyBumpsActions, DEPENDABOT_LOGIN };

if (require.main === module) {
  const [login, filesPath] = process.argv.slice(2);
  let result;
  try {
    const files = JSON.parse(require('fs').readFileSync(filesPath, 'utf8'));
    result = evaluate(login, files);
  } catch (e) {
    result = { exempt: false, reason: `error: ${e.message}` };
  }
  process.stdout.write(JSON.stringify(result) + '\n');
  process.exit(result.exempt ? 0 : 1);
}
