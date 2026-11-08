#!/usr/bin/env bash
set -euo pipefail
# containment-check.sh — Verify containment infrastructure is available

docker_available=false
base_image=false
containers_running=0
last_build="unknown"

if command -v docker &>/dev/null; then
  if timeout 3 docker info >/dev/null 2>&1; then
    docker_available=true
    if docker image inspect savia-contained:latest >/dev/null 2>&1; then
      base_image=true
      last_build=$(docker image inspect savia-contained:latest --format '{{.Created}}' 2>/dev/null | cut -d. -f1 || echo "unknown")
    fi
    # A failing `docker ps` must not abort the report under set -e/pipefail.
    if ps_out=$(docker ps -q 2>/dev/null); then
      containers_running=$(printf '%s' "$ps_out" | grep -c . || true)
    fi
  fi
fi

if [[ "${1:-}" == "--json" ]]; then
  cat <<JSONEOF
{
  "docker_available": $docker_available,
  "base_image": $base_image,
  "containers_running": $containers_running,
  "last_build": "$last_build"
}
JSONEOF
else
  echo "Containment Infrastructure Status"
  echo "================================="
  echo "Docker daemon:    $($docker_available && echo 'AVAILABLE' || echo 'UNAVAILABLE')"
  echo "Base image:       $($base_image && echo "BUILT ($last_build)" || echo 'MISSING')"
  echo "Containers:       $containers_running running"
  echo ""
  if $docker_available && $base_image; then
    echo "Status: READY — containment operational"
    exit 0
  elif $docker_available; then
    echo "Status: PARTIAL — Docker available but base image not built"
    echo "Run: docker build -t savia-contained:latest containment/"
    exit 1
  else
    echo "Status: UNAVAILABLE — N-contenido and N-hostil execution disabled"
    exit 1
  fi
fi
