#!/usr/bin/env bash
# Bootstraps the monitoring stack with provisioned dashboards and alert rules.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${MONITORING_DIR}"

echo "==> Monitoring bootstrap"
echo "    directory: ${MONITORING_DIR}"

if [[ ! -f .env ]]; then
  echo "==> Creating .env from .env.example"
  cp .env.example .env
  echo "    Edit monitoring/.env with your domain, port, and Grafana credentials before going live."
fi

# shellcheck disable=SC1091
set -a
source .env
set +a

required_paths=(
  grafana/provisioning/datasources/datasources.yml
  grafana/provisioning/dashboards/dashboards.yml
  grafana/provisioning/alerting/rules.yml
  grafana/provisioning/alerting/contactpoints.yml
  grafana/provisioning/alerting/policies.yml
  grafana/dashboards/host-overview.json
  grafana/dashboards/docker-containers.json
  prometheus/alerts.yml
  prometheus.yml
  docker-compose.yml
)

echo "==> Checking provisioning files"
missing=0
for path in "${required_paths[@]}"; do
  if [[ -f "${path}" ]]; then
    echo "    OK  ${path}"
  else
    echo "    MISSING  ${path}"
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  echo "ERROR: required provisioning files are missing."
  exit 1
fi

network_name="${NETWORK_NAME:-production_network}"
if ! docker network inspect "${network_name}" >/dev/null 2>&1; then
  echo "==> Creating Docker network: ${network_name}"
  docker network create "${network_name}"
fi

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

echo "==> Starting monitoring stack"
compose up -d

echo "==> Waiting for Grafana"
for _ in $(seq 1 30); do
  if compose ps grafana 2>/dev/null | grep -Eiq 'up|running'; then
    break
  fi
  sleep 2
done

echo
echo "Monitoring is up with:"
echo "  - Prometheus datasource (auto-provisioned)"
echo "  - Dashboards: Host Overview, Docker Containers"
echo "  - Grafana alert rules: CPU, memory, disk, exporter down"
echo "  - Prometheus alert rules: host + container thresholds"
echo "  - SMTP email contact point (from .env)"
echo
echo "Open Grafana at: ${GRAFANA_ROOT_URL}"
echo "Login with: ${GRAFANA_ADMIN_USER} / (password from .env)"
echo
echo "In Grafana:"
echo "  Dashboards -> Monitoring"
echo "  Alerting  -> Alert rules / Contact points"
echo
echo "Done."
