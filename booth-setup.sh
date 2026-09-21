#!/usr/bin/env bash
#
# booth-setup.sh - spin up a local Kestra EE instance loaded with the booth demo flows.
#
#   ./booth-setup.sh          start everything (safe to re-run)
#   ./booth-setup.sh status   is it up?
#   ./booth-setup.sh flows    re-pull the flows from GitHub
#   ./booth-setup.sh logs     tail the Kestra log
#   ./booth-setup.sh stop     stop it, keep the data
#   ./booth-setup.sh reset    delete everything and start clean
#
# Needs: Docker Desktop (running), curl. Nothing else.

set -euo pipefail

CONTAINER="kestra-booth"
VOLUME="kestra-booth-data"
IMAGE="registry.kestra.io/docker/kestra-ee:latest"
REGISTRY="registry.kestra.io"
PORT="${KESTRA_PORT:-8080}"
TENANT="default"
ADMIN_USER="${KESTRA_ADMIN_USER:-admin@kestra.io}"
ADMIN_PASS="${KESTRA_ADMIN_PASS:-Kestra42!}"
REPO="kestra-io/kestra-demo-we-are-developers"
BRANCH="main"

BASE="http://localhost:${PORT}/api/v1/${TENANT}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${HOME}/.kestra-booth"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ok()   { printf "  \033[32mok\033[0m  %s\n" "$1"; }
info() { printf "      %s\n" "$1"; }
warn() { printf "  \033[33m!\033[0m   %s\n" "$1"; }
die()  { printf "\n  \033[31mx\033[0m   %s\n\n" "$1" >&2; exit 1; }

# --------------------------------------------------------------- preflight --
preflight() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install Docker Desktop, then re-run."
  docker info >/dev/null 2>&1 || die "Docker is installed but not running. Start Docker Desktop, wait for the whale icon to settle, then re-run."
  command -v curl >/dev/null 2>&1 || die "curl is not installed."
  ok "Docker is running"
}

# ----------------------------------------------------------------- license --
# Needs three values. The license ID and fingerprint double as the registry
# login, which is how we pull the EE image.
load_license() {
  local envfile="${HERE}/license.env"
  if [[ -f "$envfile" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$envfile"; set +a
    ok "Read license from license.env"
  fi

  if [[ -z "${KESTRA_LICENSE_ID:-}" ]]; then
    bold ""
    bold "Enter your Kestra license details (Rob sends these):"
    read -r -p "  License ID: " KESTRA_LICENSE_ID
  fi
  if [[ -z "${KESTRA_LICENSE_FINGERPRINT:-}" ]]; then
    read -r -p "  Fingerprint: " KESTRA_LICENSE_FINGERPRINT
  fi
  if [[ -z "${KESTRA_LICENSE_KEY:-}" ]]; then
    local keyfile
    read -r -p "  Path to the license key file: " keyfile
    keyfile="${keyfile/#\~/$HOME}"
    [[ -f "$keyfile" ]] || die "No file at: $keyfile"
    KESTRA_LICENSE_KEY="$(cat "$keyfile")"
  fi

  [[ -n "${KESTRA_LICENSE_ID:-}" ]]          || die "License ID is required."
  [[ -n "${KESTRA_LICENSE_FINGERPRINT:-}" ]] || die "Fingerprint is required."
  [[ -n "${KESTRA_LICENSE_KEY:-}" ]]         || die "License key is required."

  # Save for next time so this is a one-off.
  if [[ ! -f "$envfile" ]]; then
    umask 077
    {
      echo "KESTRA_LICENSE_ID='${KESTRA_LICENSE_ID}'"
      echo "KESTRA_LICENSE_FINGERPRINT='${KESTRA_LICENSE_FINGERPRINT}'"
      printf "KESTRA_LICENSE_KEY='%s'\n" "${KESTRA_LICENSE_KEY}"
    } > "$envfile"
    ok "Saved license.env so you only enter this once"
  fi
  ok "License loaded"
}

# ------------------------------------------------------------------- image --
pull_image() {
  info "Logging in to ${REGISTRY}..."
  printf '%s' "${KESTRA_LICENSE_FINGERPRINT}" \
    | docker login "${REGISTRY}" --username "${KESTRA_LICENSE_ID}" --password-stdin >/dev/null 2>&1 \
    || die "Registry login failed. Double-check the License ID and Fingerprint - they are also the registry username and password."
  ok "Authenticated to the Kestra registry"

  info "Pulling ${IMAGE} (a few minutes the first time)..."
  docker pull "${IMAGE}" >/dev/null || die "Could not pull the Enterprise image."
  ok "Image ready: $(docker image inspect "${IMAGE}" --format '{{index .RepoTags 0}}')"
}

# ------------------------------------------------------------------ config --
write_config() {
  mkdir -p "${WORKDIR}"
  local conf="${WORKDIR}/application.yml"
  local keyfile="${WORKDIR}/.enc-key"

  # Stable encryption key across restarts, or secrets break after a reset.
  if [[ ! -f "$keyfile" ]]; then
    ( umask 077; openssl rand -base64 32 > "$keyfile" 2>/dev/null ) \
      || ( umask 077; head -c 32 /dev/urandom | base64 > "$keyfile" )
  fi

  {
    echo "kestra:"
    echo "  encryption:"
    echo "    secret-key: $(tr -d '\n' < "$keyfile")"
    echo "  security:"
    echo "    super-admin:"
    echo "      username: ${ADMIN_USER}"
    echo "      password: ${ADMIN_PASS}"
    echo "  ee:"
    echo "    worker:"
    echo "      auth:"
    echo "        enabled: false"
    echo "    license:"
    echo "      id: ${KESTRA_LICENSE_ID}"
    echo "      fingerprint: ${KESTRA_LICENSE_FINGERPRINT}"
    echo "      key: |"
    printf '%s\n' "${KESTRA_LICENSE_KEY}" | sed 's/^/        /'
  } > "$conf"
  chmod 600 "$conf"
  ok "Wrote config to ${conf}"
}

# --------------------------------------------------------------- container --
start_container() {
  if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    info "Removing the previous ${CONTAINER} container..."
    docker rm -f "${CONTAINER}" >/dev/null
  fi
  docker volume create "${VOLUME}" >/dev/null

  docker run -d \
    --name "${CONTAINER}" \
    -p "${PORT}:8080" \
    -v "${VOLUME}:/app/storage" \
    -v "${WORKDIR}/application.yml:/etc/config/application.yml:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --restart unless-stopped \
    "${IMAGE}" server local --config /etc/config/application.yml >/dev/null \
    || die "Container failed to start. Run: docker logs ${CONTAINER}"
  ok "Container ${CONTAINER} started on port ${PORT}"
}

wait_ready() {
  info "Waiting for Kestra to come up (up to 3 minutes)..."
  local i code
  for i in $(seq 1 90); do
    code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASS}" "${BASE}/flows/search?size=1" || true)"
    if [[ "$code" == "200" ]]; then ok "Kestra is up"; return 0; fi
    if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
      docker logs --tail 40 "${CONTAINER}" >&2 || true
      die "The container stopped. The log above usually says why - most often an invalid license."
    fi
    sleep 2
  done
  docker logs --tail 40 "${CONTAINER}" >&2 || true
  die "Kestra did not become ready in time. Log above; full log: docker logs ${CONTAINER}"
}

# ------------------------------------------------------------------- flows --
deploy_flows() {
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  info "Downloading flows from ${REPO}@${BRANCH}..."
  curl -fsSL "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}" \
    | tar -xz -C "$tmp" 2>/dev/null \
    || die "Could not download the flows. Check your internet connection."

  local dir; dir="$(find "$tmp" -type d -name flows -maxdepth 2 | head -1)"
  [[ -n "$dir" ]] || die "No flows/ directory in the repository archive."

  local n=0 f code
  for f in "$dir"/*.yaml "$dir"/*.yml; do
    [[ -e "$f" ]] || continue
    code="$(curl -s -o /dev/null -m 30 -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -X POST -F "fileUpload=@${f}" "${BASE}/flows/import")"
    if [[ "$code" == "200" ]]; then
      n=$((n+1))
    else
      warn "$(basename "$f") failed to import (HTTP $code)"
    fi
  done
  [[ "$n" -gt 0 ]] || die "No flows imported."
  ok "Imported ${n} flows"
}

verify_tools() {
  local url="http://localhost:${PORT}/api/v1/${TENANT}/mcp/default"
  local sid
  sid="$(curl -s -m 20 -D - -o /dev/null -u "${ADMIN_USER}:${ADMIN_PASS}" \
      -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
      -X POST -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"setup","version":"1"}}}' \
      "$url" 2>/dev/null | grep -i 'mcp-session-id' | tr -d '\r' | awk '{print $2}')"
  if [[ -z "$sid" ]]; then warn "Could not reach the MCP server to count tools (the flows are still deployed)."; return 0; fi

  curl -s -m 15 -u "${ADMIN_USER}:${ADMIN_PASS}" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -H "Mcp-Session-Id: $sid" \
    -X POST -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$url" >/dev/null 2>&1

  local count
  count="$(curl -s -m 20 -u "${ADMIN_USER}:${ADMIN_PASS}" -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' -H "Mcp-Session-Id: $sid" \
    -X POST -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "$url" 2>/dev/null \
    | tr ',' '\n' | grep -c '"name"' || true)"

  if [[ "${count:-0}" -ge 6 ]]; then ok "MCP server is serving ${count} tools"
  else warn "MCP reported ${count:-0} tools, expected 6. Check the Flows page in the UI."; fi
}

summary() {
  cat <<EOF

$(bold "Ready.")

  Kestra UI     http://localhost:${PORT}/ui
  Username      ${ADMIN_USER}
  Password      ${ADMIN_PASS}

  MCP endpoint  http://localhost:${PORT}/api/v1/${TENANT}/mcp/default
  Auth header   Authorization: Basic $(printf '%s' "${ADMIN_USER}:${ADMIN_PASS}" | base64)

  Next: paste the MCP endpoint and auth header into Claude Desktop.
  Full instructions are in BOOTH.md in the repo.

  Stop it later with:  ./booth-setup.sh stop

EOF
}

# -------------------------------------------------------------- subcommands --
cmd_up() {
  bold ""
  bold "Setting up the Kestra booth demo"
  bold ""
  preflight
  load_license
  pull_image
  write_config
  start_container
  wait_ready
  deploy_flows
  verify_tools
  summary
}

cmd_flows() {
  preflight
  wait_ready
  deploy_flows
  verify_tools
  echo
}

cmd_status() {
  if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    local code
    code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASS}" "${BASE}/flows/search?size=1" || true)"
    if [[ "$code" == "200" ]]; then
      ok "Running and healthy - http://localhost:${PORT}/ui"
    else
      warn "Container is running but the API returned ${code}. It may still be starting."
    fi
  else
    warn "Not running. Start it with: ./booth-setup.sh"
  fi
}

cmd_logs()  { docker logs -f --tail 100 "${CONTAINER}"; }

cmd_stop()  {
  docker stop "${CONTAINER}" >/dev/null 2>&1 && ok "Stopped. Your data is kept - re-run ./booth-setup.sh to start again." \
    || warn "It was not running."
}

cmd_reset() {
  printf "This deletes the container, its data volume and the saved config. Type yes to continue: "
  read -r a
  [[ "$a" == "yes" ]] || { info "Cancelled."; exit 0; }
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
  rm -rf "${WORKDIR}"
  ok "Reset. Run ./booth-setup.sh for a clean install."
}

case "${1:-up}" in
  up|"")   cmd_up ;;
  flows)   cmd_flows ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  stop)    cmd_stop ;;
  reset)   cmd_reset ;;
  *) die "Unknown command '${1}'. Use: up | flows | status | logs | stop | reset" ;;
esac
