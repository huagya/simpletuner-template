#!/usr/bin/env bash
# Feasibility spike: SimpleTuner v4.9.3 WebUI on CPU, behind Caddy basic auth.
# Exits non-zero on any failed check. Safe to re-run; it wipes only its own work dir.
set -euo pipefail

ST_VERSION="4.9.3"
ST_COMMIT="82a589d99875e7284bb1abe1ca5479f327b78dcf"
PY_BIN="${PY_BIN:-python3.12}"
TORCH_SPEC="torch==2.11.0+cpu"
TV_SPEC="torchvision==0.26.0+cpu"
TA_SPEC="torchaudio==2.11.0+cpu"
CADDY_VERSION="2.11.7"
# Caddy's checksums.txt is SHA-512, not SHA-256.
CADDY_SHA512="a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7"
CADDY_URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"

WEB_USERNAME="${WEB_USERNAME:-admin}"
WEB_PASSWORD="${WEB_PASSWORD:-ci-password-123456}"
GUI_ADMIN_USER="${GUI_ADMIN_USER:-sttadmin}"
GUI_ADMIN_PASSWORD="${GUI_ADMIN_PASSWORD:-gui-admin-pass-123}"
GUI_ADMIN_EMAIL="${GUI_ADMIN_EMAIL:-admin@example.com}"

APP_PORT="${APP_PORT:-18001}"
PROXY_PORT="${PROXY_PORT:-8001}"
READY_TIMEOUT="${READY_TIMEOUT:-180}"

WORK="${STT_WORK:-/tmp/stt-feasibility}"
VENV="${STT_VENV:-${WORK}/venv}"
STATE_DIR="${WORK}/state"
CONFIG_DIR="${WORK}/config"
WORKSPACE_DIR="${WORK}/workspace"
LOG_DIR="${WORK}/logs"
BIN_DIR="${WORK}/bin"

APP_URL="http://127.0.0.1:${APP_PORT}"
PROXY_URL="http://127.0.0.1:${PROXY_PORT}"
RUNPOD_ORIGIN="https://abc123-${PROXY_PORT}.proxy.runpod.net"

SERVER_PID=""
CADDY_PID=""

fail() {
  echo "FAIL: $*" >&2
  if [[ -f "${LOG_DIR}/simpletuner.log" ]]; then
    echo "----- last 40 lines of simpletuner.log -----" >&2
    tail -n 40 "${LOG_DIR}/simpletuner.log" >&2 || true
  fi
  if [[ -f "${LOG_DIR}/caddy.log" ]]; then
    echo "----- last 40 lines of caddy.log -----" >&2
    tail -n 40 "${LOG_DIR}/caddy.log" >&2 || true
  fi
  exit 1
}

pass() {
  echo "PASS: $*"
}

cleanup() {
  local rc=$?
  if [[ -n "${CADDY_PID}" ]] && kill -0 "${CADDY_PID}" 2>/dev/null; then
    kill "${CADDY_PID}" 2>/dev/null || true
    wait "${CADDY_PID}" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "feasibility_proxy_test.sh failed (exit ${rc})" >&2
  fi
}
trap cleanup EXIT

http_code() {
  # Usage: http_code OUTFILE -- curl args
  local outfile="$1"
  shift
  curl -sS -o "${outfile}" -w '%{http_code}' "$@" || echo "CURL_FAIL"
}

require_code() {
  local name="$1" got="$2" expected="$3"
  if [[ "${got}" != "${expected}" ]]; then
    fail "${name}: HTTP ${got}, expected ${expected}"
  fi
  pass "${name}: HTTP ${got}"
}

echo "== SimpleTuner feasibility proxy test =="
echo "work dir: ${WORK}"
command -v "${PY_BIN}" >/dev/null || fail "${PY_BIN} is not installed"
"${PY_BIN}" - <<'PY' || fail "Python is not 3.12.x"
import sys
raise SystemExit(0 if sys.version_info[:2] == (3, 12) else 1)
PY

if ! python3 - "${APP_PORT}" "${PROXY_PORT}" <<'PY'
import socket, sys
busy = []
for raw in sys.argv[1:]:
    port = int(raw)
    sock = socket.socket()
    try:
        sock.bind(("127.0.0.1", port))
    except OSError:
        busy.append(port)
    finally:
        sock.close()
if busy:
    print("busy", ",".join(str(p) for p in busy))
    raise SystemExit(1)
PY
then
  fail "port ${APP_PORT} or ${PROXY_PORT} is already in use"
fi

rm -rf "${STATE_DIR}" "${CONFIG_DIR}" "${WORKSPACE_DIR}" "${LOG_DIR}"
mkdir -p "${STATE_DIR}" "${CONFIG_DIR}" "${WORKSPACE_DIR}" "${LOG_DIR}" "${BIN_DIR}"

if [[ ! -x "${VENV}/bin/python" ]]; then
  echo "Creating venv at ${VENV}"
  "${PY_BIN}" -m venv "${VENV}" || fail "venv creation failed"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install --upgrade pip setuptools wheel || fail "pip upgrade failed"

CONSTRAINTS="${WORK}/constraints.txt"
cat >"${CONSTRAINTS}" <<EOF
${TORCH_SPEC}
${TV_SPEC}
${TA_SPEC}
EOF

if ! python - <<'PY'
import simpletuner, torch
assert simpletuner.__version__ == "4.9.3", simpletuner.__version__
assert torch.__version__ == "2.11.0+cpu", torch.__version__
print("reuse venv", simpletuner.__version__, torch.__version__)
PY
then
  echo "Installing CPU torch ${TORCH_SPEC} from the PyTorch CPU index"
  python -m pip install \
    --index-url https://download.pytorch.org/whl/cpu \
    "${TORCH_SPEC}" "${TV_SPEC}" "${TA_SPEC}" \
    || fail "CPU torch install failed"
  echo "Installing simpletuner[cpu]==${ST_VERSION} without replacing the CPU torch wheel"
  python -m pip install \
    --extra-index-url https://download.pytorch.org/whl/cpu \
    -c "${CONSTRAINTS}" \
    "simpletuner[cpu]==${ST_VERSION}" \
    || fail "simpletuner install failed"
fi

python - <<PY || fail "installed versions do not match the pin"
import simpletuner, torch
print("simpletuner", simpletuner.__version__)
print("torch", torch.__version__, "cuda_available", torch.cuda.is_available())
assert simpletuner.__version__ == "${ST_VERSION}"
assert torch.__version__ == "2.11.0+cpu", torch.__version__
assert torch.cuda.is_available() is False
PY

if [[ ! -x "${BIN_DIR}/caddy" ]]; then
  echo "Downloading Caddy ${CADDY_VERSION}"
  tmp_tar="${WORK}/caddy.tar.gz"
  curl -fsSL -o "${tmp_tar}" "${CADDY_URL}" || fail "Caddy download failed"
  echo "${CADDY_SHA512}  ${tmp_tar}" | sha512sum -c - || fail "Caddy checksum mismatch"
  tar -C "${BIN_DIR}" -xzf "${tmp_tar}" caddy || fail "Caddy extract failed"
  chmod +x "${BIN_DIR}/caddy"
fi
"${BIN_DIR}/caddy" version || fail "caddy version failed"

HASH="$("${BIN_DIR}/caddy" hash-password --plaintext "${WEB_PASSWORD}")"
[[ -n "${HASH}" ]] || fail "caddy hash-password returned an empty hash"
cat >"${WORK}/Caddyfile" <<EOF
{
	admin off
	auto_https off
}
http://127.0.0.1:${PROXY_PORT} {
	basic_auth {
		${WEB_USERNAME} "${HASH}"
	}
	reverse_proxy 127.0.0.1:${APP_PORT} {
		flush_interval -1
	}
}
EOF

export SIMPLETUNER_STATE_DIR="${STATE_DIR}"
export SIMPLETUNER_CONFIG_DIR="${CONFIG_DIR}"
export SIMPLETUNER_WORKSPACE="${WORKSPACE_DIR}"
export SIMPLETUNER_HOST="127.0.0.1"
export SIMPLETUNER_PORT="${APP_PORT}"
export HF_HUB_DISABLE_TELEMETRY=1
export PYTHONUNBUFFERED=1

echo "Starting simpletuner server --host 127.0.0.1 --port ${APP_PORT}"
# The server writes debug.log in the current directory. Stay inside the work dir.
cd "${WORK}"
START_NS="$(date +%s%N)"
simpletuner server --host 127.0.0.1 --port "${APP_PORT}" >"${LOG_DIR}/simpletuner.log" 2>&1 &
SERVER_PID=$!

ready=0
for _ in $(seq 1 "${READY_TIMEOUT}"); do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    fail "simpletuner server exited before it became ready"
  fi
  code="$(http_code "${LOG_DIR}/ready-body.html" "${APP_URL}/web/trainer")"
  if [[ "${code}" == "200" ]]; then
    ready=1
    break
  fi
  sleep 1
done
END_NS="$(date +%s%N)"
ELAPSED_MS="$(( (END_NS - START_NS) / 1000000 ))"
if [[ "${ready}" != "1" ]]; then
  fail "simpletuner server did not return HTTP 200 on /web/trainer within ${READY_TIMEOUT}s (last code ${code:-none})"
fi
pass "simpletuner server ready on 127.0.0.1:${APP_PORT} in ${ELAPSED_MS} ms (no GPU)"
echo "startup_ms=${ELAPSED_MS}"

if ! grep -q "<title>SimpleTuner" "${LOG_DIR}/ready-body.html"; then
  fail "direct /web/trainer HTML does not contain a SimpleTuner title"
fi
pass "direct /web/trainer HTML contains a SimpleTuner title"

echo "Starting Caddy basic auth on 127.0.0.1:${PROXY_PORT}"
"${BIN_DIR}/caddy" run --config "${WORK}/Caddyfile" >"${LOG_DIR}/caddy.log" 2>&1 &
CADDY_PID=$!
caddy_ready=0
for _ in $(seq 1 30); do
  if ! kill -0 "${CADDY_PID}" 2>/dev/null; then
    fail "caddy exited during startup"
  fi
  code="$(http_code "${LOG_DIR}/proxy-unauth.html" "${PROXY_URL}/web/trainer")"
  if [[ "${code}" == "401" ]]; then
    caddy_ready=1
    break
  fi
  sleep 0.5
done
[[ "${caddy_ready}" == "1" ]] || fail "proxy did not return 401 for an unauthenticated request (last code ${code:-none})"
pass "unauthenticated proxy request gets 401"

auth_code="$(http_code "${LOG_DIR}/proxy-auth.html" -u "${WEB_USERNAME}:${WEB_PASSWORD}" "${PROXY_URL}/web/trainer")"
require_code "authenticated /web/trainer through proxy" "${auth_code}" "200"
if ! grep -q "<title>SimpleTuner" "${LOG_DIR}/proxy-auth.html"; then
  fail "authenticated proxy page is not the SimpleTuner trainer"
fi
pass "authenticated proxy page is the SimpleTuner trainer"

python3 - "${LOG_DIR}/proxy-auth.html" <<'PY' || fail "trainer HTML contains Japanese UI text (unexpected)"
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
if re.search(r"[\u3040-\u30ff]", text):
    raise SystemExit(1)
print("PASS: trainer HTML has no hiragana/katakana")
PY

direct_me="$(http_code "${LOG_DIR}/direct-me.json" "${APP_URL}/api/users/me")"
require_code "direct /api/users/me with no credentials (auto-admin)" "${direct_me}" "200"
python3 - "${LOG_DIR}/direct-me.json" <<'PY' || fail "auto-admin user is not the local placeholder"
import json, sys
user = json.load(open(sys.argv[1]))
print("auto_admin_user", user.get("username"), "is_admin", user.get("is_admin"))
assert user.get("username") == "local", user
assert user.get("is_admin") is True
PY
pass "no-user startup auto-authenticates as local admin on the app port"
if grep -q "Single-user mode" "${LOG_DIR}/simpletuner.log"; then
  pass "server log records single-user mode"
  grep "Single-user mode" "${LOG_DIR}/simpletuner.log" | head -n 5
else
  echo "WARN: single-user log line not found; API evidence above still stands"
fi

echo "Checking SSE through the proxy"
set +e
curl -sS -N --max-time 8 \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -H 'Accept: text/event-stream' \
  "${PROXY_URL}/api/events" >"${LOG_DIR}/sse.txt" 2>"${LOG_DIR}/sse.err"
sse_rc=$?
set -e
if [[ "${sse_rc}" -ne 0 && "${sse_rc}" -ne 28 ]]; then
  cat "${LOG_DIR}/sse.err" >&2 || true
  fail "SSE curl failed with status ${sse_rc}"
fi
if ! grep -Eq 'event:|data:' "${LOG_DIR}/sse.txt"; then
  echo "----- SSE body -----" >&2
  cat "${LOG_DIR}/sse.txt" >&2 || true
  fail "SSE stream through the proxy produced no event/data frames"
fi
pass "SSE /api/events streams through Caddy (flush_interval -1)"
echo "----- SSE excerpt -----"
head -n 8 "${LOG_DIR}/sse.txt"

echo "Saving a config through the proxy with a RunPod-style Origin"
save_body="${LOG_DIR}/save.json"
save_code="$(http_code "${save_body}" \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -H "Origin: ${RUNPOD_ORIGIN}" \
  -X POST "${PROXY_URL}/api/configs/environments" \
  --data '{"name":"feas-pixart","model_family":"pixart_sigma","model_type":"lora","model_flavour":"900M-1024-v0.6","description":"feasibility save"}')"
require_code "config create through proxy with RunPod Origin and no CSRF token" "${save_code}" "200"
python3 - "${save_body}" "${CONFIG_DIR}" <<'PY' || fail "config save response or on-disk file is wrong"
import json, sys
from pathlib import Path
body = json.load(open(sys.argv[1]))
config_dir = Path(sys.argv[2])
print("save_keys", sorted(body)[:12] if isinstance(body, dict) else type(body))
candidates = list(config_dir.rglob("config.json"))
print("config_json_files", [str(p) for p in candidates])
found = False
for path in candidates:
    data = json.loads(path.read_text())
    blob = json.dumps(data)
    if "feas-pixart" in blob or "pixart_sigma" in blob:
        found = True
        print("saved_file", path)
        break
assert found, "pixart config was not written"
PY
pass "config save persisted under SIMPLETUNER_CONFIG_DIR"

evil_code="$(http_code "${LOG_DIR}/evil.json" \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://evil.example' \
  -X POST "${PROXY_URL}/api/configs/" \
  --data '{"name":"feas-evil-origin","config":{"--model_family":"stable_cascade","--model_type":"lora"},"description":"foreign origin"}')"
if [[ "${evil_code}" == "403" ]]; then
  fail "foreign Origin was rejected with 403; CSRF/origin enforcement is stricter than the source read predicted"
fi
pass "foreign Origin config POST was not rejected (HTTP ${evil_code}); Origin is not an allow-list"

echo "Listing model families from the running server"
fam_code="$(http_code "${LOG_DIR}/families.json" -u "${WEB_USERNAME}:${WEB_PASSWORD}" "${PROXY_URL}/api/models")"
require_code "GET /api/models through proxy" "${fam_code}" "200"
python3 - "${LOG_DIR}/families.json" <<'PY' || fail "PixArt Sigma or Stable Cascade missing from the live family list"
import json, sys
data = json.load(open(sys.argv[1]))
families = data.get("families") or data
print("family_count", len(families))
need = {"pixart", "pixart_sigma", "stable_cascade"}
present = sorted(need.intersection(families))
print("present", present)
assert "stable_cascade" in families, families
assert "pixart" in families or "pixart_sigma" in families, families
PY

for family in pixart pixart_sigma stable_cascade; do
  code="$(http_code "${LOG_DIR}/model-${family}.json" -u "${WEB_USERNAME}:${WEB_PASSWORD}" "${PROXY_URL}/api/models/${family}")"
  echo "model ${family} HTTP ${code}"
  if [[ "${code}" == "200" ]]; then
    python3 - "${LOG_DIR}/model-${family}.json" "${family}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(sys.argv[2], "name=", data.get("name") or data.get("display_name"), "flavours=", data.get("flavours"))
PY
  fi
done

echo "Creating a real GUI admin (this disables single-user auto-admin)"
simpletuner auth setup \
  --email "${GUI_ADMIN_EMAIL}" \
  --username "${GUI_ADMIN_USER}" \
  --password "${GUI_ADMIN_PASSWORD}" \
  || fail "simpletuner auth setup failed"

after_direct="$(http_code "${LOG_DIR}/after-direct-me.json" "${APP_URL}/api/users/me")"
require_code "direct /api/users/me after real admin exists, no session" "${after_direct}" "401"
after_proxy="$(http_code "${LOG_DIR}/after-proxy-me.json" -u "${WEB_USERNAME}:${WEB_PASSWORD}" "${PROXY_URL}/api/users/me")"
require_code "proxy basic auth is not enough for /api/users/me once a real admin exists" "${after_proxy}" "401"

login_code="$(http_code "${LOG_DIR}/login.json" \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -c "${LOG_DIR}/gui.cookies" \
  -H 'Content-Type: application/json' \
  -X POST "${PROXY_URL}/api/auth/login" \
  --data "{\"username\":\"${GUI_ADMIN_USER}\",\"password\":\"${GUI_ADMIN_PASSWORD}\"}")"
require_code "SimpleTuner login through the proxy" "${login_code}" "200"
both_code="$(http_code "${LOG_DIR}/both-me.json" \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -b "${LOG_DIR}/gui.cookies" \
  "${PROXY_URL}/api/users/me")"
require_code "proxy basic auth plus GUI session" "${both_code}" "200"
python3 - "${LOG_DIR}/both-me.json" "${GUI_ADMIN_USER}" <<'PY' || fail "session user is not the created admin"
import json, sys
user = json.load(open(sys.argv[1]))
print("session_user", user.get("username"))
assert user.get("username") == sys.argv[2]
PY
pass "real admin disables auto-admin; the GUI then requires its own login in addition to the proxy"

echo
echo "==== summary ===="
echo "simpletuner=${ST_VERSION} commit=${ST_COMMIT}"
echo "torch=2.11.0+cpu python=$(python -V)"
echo "caddy=${CADDY_VERSION}"
echo "app=127.0.0.1:${APP_PORT} proxy=127.0.0.1:${PROXY_PORT} startup_ms=${ELAPSED_MS}"
echo "ALL CHECKS PASSED"
