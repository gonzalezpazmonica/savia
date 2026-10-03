#!/bin/bash
# Savia School: Core educational vertical management library
# Security & Privacy Critical — GDPR/LOPD compliant
# Max 150 lines

set -euo pipefail
umask 077

SCHOOL_BASE="${SCHOOL_BASE:-.}"
SCHOOL_ROOT="${SCHOOL_BASE}/school-savia"
SCHOOL_CONFIG="${SCHOOL_ROOT}/.school-config.md"
SECURITY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/savia-school-security.sh"
export SCHOOL_BASE

die() { echo "❌ $*" >&2; exit 1; }
usage() { echo "Usage: $0 {setup|enroll|project-create|submit|evaluate|progress|export|forget} ..." >&2; exit 2; }
need() { [ "$1" -ge "$2" ] || usage; }
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] || die "Invalid ${2:-alias}: use [A-Za-z0-9_-], sin espacios ni barras"; }
enrolled() { valid_name "$1"; [ -d "${SCHOOL_ROOT}/classroom/$1" ] || die "Student not enrolled: $1"; }
security() { bash "${SECURITY}" "$@"; }

# ── School Setup ──────────────────────────────────────────────────────────────
school_setup() {
  local school_name="$1" course="$2" subject="$3"
  [ ! -e "${SCHOOL_CONFIG}" ] || die "School already set up: ${SCHOOL_CONFIG}"
  mkdir -p "${SCHOOL_ROOT}"/{classroom,teacher/{evaluations,rubrics},templates,shared}
  chmod 700 "${SCHOOL_ROOT}"
  cat > "${SCHOOL_CONFIG}" <<EOF
# Savia School Configuration
school_name: ${school_name}
course: ${course}
subject: ${subject}
teacher: ${USER:-$(id -un)}
created_at: $(date -Iseconds)
# GDPR/LOPD Compliance
gdpr_enabled: true
consent_required: true
data_minimization: true
encryption_at_rest: true
EOF
  echo "✅ School setup: ${school_name}"
}

# ── Student Enrollment ────────────────────────────────────────────────────────
school_enroll() {
  local alias="$1"
  valid_name "${alias}"
  [ -d "${SCHOOL_ROOT}/classroom" ] || die "School not set up: ${SCHOOL_ROOT}"
  mkdir -p "${SCHOOL_ROOT}/classroom/${alias}"/{projects,portfolio}
  chmod 700 "${SCHOOL_ROOT}/classroom/${alias}"
  touch "${SCHOOL_ROOT}/classroom/${alias}/portfolio.md"
  echo "# Student: ${alias}" > "${SCHOOL_ROOT}/classroom/${alias}/progress.md"
  echo "✅ Enrolled: ${alias}"
}

# ── Create Project (nunca sobrescribe trabajo existente) ──────────────────────
school_project_create() {
  local alias="$1" project_name="$2"
  enrolled "${alias}"; valid_name "${project_name}" "project name"
  local proj_dir="${SCHOOL_ROOT}/classroom/${alias}/projects/${project_name}"
  [ ! -e "${proj_dir}" ] || die "Project already exists: ${project_name}"
  mkdir -p "${proj_dir}"
  cat > "${proj_dir}/README.md" <<EOF
# Project Template
- **Status**: Draft
- **Started**: $(date -I)
- **Submitted**: None
EOF
  echo "✅ Project created: ${project_name}"
}

# ── Submit Project ────────────────────────────────────────────────────────────
school_submit() {
  local alias="$1" project_name="$2"
  enrolled "${alias}"; valid_name "${project_name}" "project name"
  local proj_dir="${SCHOOL_ROOT}/classroom/${alias}/projects/${project_name}"
  [ -d "${proj_dir}" ] || die "Project not found: ${project_name}"
  date -Iseconds > "${proj_dir}/.submitted"
  echo "✅ Submitted: ${project_name}"
}

# ── Evaluate Student Work (la nota viaja por stdin, no por argv) ──────────────
school_evaluate() {
  local alias="$1" project_name="$2" grade="$3"
  enrolled "${alias}"; valid_name "${project_name}" "project name"
  printf 'Grade: %s | Project: %s\n' "${grade}" "${project_name}" | \
    security encrypt-eval "${alias}" - >/dev/null || die "Evaluation NOT stored: encryption failed"
  echo "✅ Evaluation encrypted: ${alias}/${project_name}"
}

# ── Show Student Progress ─────────────────────────────────────────────────────
school_progress() {
  local alias="$1"
  enrolled "${alias}"
  echo "📊 Progress: ${alias}"
  [ ! -f "${SCHOOL_ROOT}/classroom/${alias}/progress.md" ] || \
    head -20 "${SCHOOL_ROOT}/classroom/${alias}/progress.md"
}

# ── GDPR Data Export (Art. 15): carpeta + evaluaciones cifradas, tar 0600 ─────
school_export() {
  local alias="$1" parts
  enrolled "${alias}"
  local export_file="${SCHOOL_EXPORT_DIR:-output}/gdpr-export-${alias}-$(date +%Y%m%d).tar.gz"
  parts=("classroom/${alias}")
  [ ! -d "${SCHOOL_ROOT}/teacher/evaluations/${alias}" ] || parts+=("teacher/evaluations/${alias}")
  security audit-access "${alias}" "gdpr-export" >/dev/null || die "Audit failed: nothing exported"
  mkdir -p "$(dirname "${export_file}")"
  tar czf "${export_file}" -C "${SCHOOL_ROOT}" "${parts[@]}" || \
    { rm -f "${export_file}"; die "GDPR export failed: ${alias}"; }
  chmod 600 "${export_file}"
  echo "✅ GDPR export: ${export_file}"
}

# ── GDPR Right to Erasure (Art. 17): auditoría primero, falla en cerrado ──────
school_forget() {
  local alias="$1"
  valid_name "${alias}"
  [ -d "${SCHOOL_ROOT}/classroom/${alias}" ] || [ -d "${SCHOOL_ROOT}/teacher/evaluations/${alias}" ] || \
    die "Student not found: ${alias}"
  security audit-access "${alias}" "deletion" >/dev/null || die "Audit failed: nothing deleted"
  rm -rf "${SCHOOL_ROOT}/classroom/${alias}" "${SCHOOL_ROOT}/teacher/evaluations/${alias}"
  echo "✅ Deletion complete: ${alias}"
}

# ── Main dispatcher ───────────────────────────────────────────────────────────
main() {
  local n=$#
  case "${1:-help}" in
    setup) need "$n" 4; school_setup "$2" "$3" "$4" ;;
    enroll) need "$n" 2; school_enroll "$2" ;;
    project-create) need "$n" 3; school_project_create "$2" "$3" ;;
    submit) need "$n" 3; school_submit "$2" "$3" ;;
    evaluate) need "$n" 4; school_evaluate "$2" "$3" "$4" ;;
    progress) need "$n" 2; school_progress "$2" ;;
    export) need "$n" 2; school_export "$2" ;;
    forget) need "$n" 2; school_forget "$2" ;;
    *) usage ;;
  esac
}

main "$@"
