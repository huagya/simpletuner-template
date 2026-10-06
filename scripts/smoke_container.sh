#!/usr/bin/env bash
# Build (CPU torch by default) and boot the RunPod image without a GPU.
# Exits non-zero on any failed check. cu128 is the Dockerfile default;
# this VM has no GPU and a small RAM budget, so the smoke variant is CPU
# unless STT_TORCH_VARIANT=cu128.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${STT_TORCH_VARIANT:-cpu}"
IMAGE="${STT_IMAGE:-stt-runpod:smoke-${VARIANT}}"
WEB_PASSWORD="${WEB_PASSWORD:-ci-password-123456}"
WEB_USERNAME="${WEB_USERNAME:-admin}"
GUI_HOST_PORT="${STT_GUI_HOST_PORT:-18081}"
JUP_HOST_PORT="${STT_JUP_HOST_PORT:-18082}"
CLOSED_HOST_PORT="${STT_CLOSED_HOST_PORT:-18083}"
READY_TIMEOUT="${STT_READY_TIMEOUT:-180}"
NAME="stt-smoke-${VARIANT}-$$"
CLOSED_NAME="stt-closed-${VARIANT}-$$"
VOLUME="stt-smoke-data-$$"

fail() {
  echo "FAIL: $*" >&2
  if docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
    echo "----- logs ${NAME} -----" >&2
    docker logs "${NAME}" 2>&1 | tail -n 80 >&2 || true
  fi
  exit 1
}

pass() {
  echo "PASS: $*"
}

cleanup() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  docker rm -f "${CLOSED_NAME}" >/dev/null 2>&1 || true
  docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v docker >/dev/null || fail "docker is not installed or not on PATH"
docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"

python3 - "${GUI_HOST_PORT}" "${JUP_HOST_PORT}" "${CLOSED_HOST_PORT}" <<'PY' || fail "a host port is already in use"
import socket, sys
busy = []
for raw in sys.argv[1:]:
    sock = socket.socket()
    try:
        sock.bind(("127.0.0.1", int(raw)))
    except OSError:
        busy.append(raw)
    finally:
        sock.close()
if busy:
    print("busy", ",".join(busy))
    raise SystemExit(1)
PY

echo "Building ${IMAGE} TORCH_VARIANT=${VARIANT}"
docker build --build-arg "TORCH_VARIANT=${VARIANT}" -t "${IMAGE}" "${ROOT}" \
  || fail "docker build failed"
pass "image built (${IMAGE}, variant ${VARIANT})"
docker image inspect "${IMAGE}" --format 'image_bytes={{.Size}}' || true

echo "Starting ${NAME}"
docker run -d --name "${NAME}" \
  -e "WEB_PASSWORD=${WEB_PASSWORD}" \
  -e "WEB_USERNAME=${WEB_USERNAME}" \
  -p "127.0.0.1:${GUI_HOST_PORT}:8001" \
  -p "127.0.0.1:${JUP_HOST_PORT}:8888" \
  -v "${VOLUME}:/workspace" \
  "${IMAGE}" >/dev/null || fail "docker run failed"

echo "Waiting for proxy auth (up to ${READY_TIMEOUT}s)"
unauth=""
auth=""
ready=0
for _ in $(seq 1 "${READY_TIMEOUT}"); do
  unauth="$(curl -s -o /tmp/stt-smoke-unauth.html -w '%{http_code}' "http://127.0.0.1:${GUI_HOST_PORT}/web/trainer" || true)"
  auth="$(curl -s -o /tmp/stt-smoke-auth.html -u "${WEB_USERNAME}:${WEB_PASSWORD}" -w '%{http_code}' "http://127.0.0.1:${GUI_HOST_PORT}/web/trainer" || true)"
  if [[ "${unauth}" == "401" && "${auth}" == "200" ]]; then
    ready=1
    break
  fi
  if ! docker inspect -f '{{.State.Running}}' "${NAME}" 2>/dev/null | grep -qx true; then
    fail "container exited while waiting for the GUI"
  fi
  sleep 1
done
[[ "${ready}" == "1" ]] || fail "GUI proxy not ready (unauth=${unauth:-none} auth=${auth:-none})"
pass "unauthenticated GUI request gets 401"
if ! grep -q '<title>SimpleTuner' /tmp/stt-smoke-auth.html; then
  fail "authenticated GUI page is not SimpleTuner"
fi
pass "authenticated GUI page is HTTP 200 and is the SimpleTuner trainer"

jup_unauth=""
jup_auth=""
jup_ready=0
for _ in $(seq 1 60); do
  jup_unauth="$(curl -s -o /tmp/stt-smoke-jup-unauth.html -w '%{http_code}' "http://127.0.0.1:${JUP_HOST_PORT}/" || true)"
  jup_auth="$(curl -s -L -o /tmp/stt-smoke-jup-auth.html -u "${WEB_USERNAME}:${WEB_PASSWORD}" -w '%{http_code}' "http://127.0.0.1:${JUP_HOST_PORT}/" || true)"
  if [[ "${jup_unauth}" == "401" && "${jup_auth}" == "200" ]]; then
    jup_ready=1
    break
  fi
  sleep 1
done
[[ "${jup_ready}" == "1" ]] || fail "Jupyter proxy not ready (unauth=${jup_unauth:-none} auth=${jup_auth:-none})"
pass "unauthenticated Jupyter request gets 401"
if ! grep -Eqi 'jupyter' /tmp/stt-smoke-jup-auth.html; then
  fail "authenticated Jupyter body does not mention Jupyter"
fi
pass "authenticated Jupyter page is HTTP 200"

echo "Checking SSE through the proxy"
set +e
curl -sS -N --max-time 8 \
  -u "${WEB_USERNAME}:${WEB_PASSWORD}" \
  -H 'Accept: text/event-stream' \
  "http://127.0.0.1:${GUI_HOST_PORT}/api/events" > /tmp/stt-smoke-sse.txt 2>/tmp/stt-smoke-sse.err
sse_rc=$?
set -e
if [[ "${sse_rc}" -ne 0 && "${sse_rc}" -ne 28 ]]; then
  cat /tmp/stt-smoke-sse.err >&2 || true
  fail "SSE curl failed with status ${sse_rc}"
fi
if ! grep -Eq 'event:|data:' /tmp/stt-smoke-sse.txt; then
  echo "----- SSE body -----" >&2
  cat /tmp/stt-smoke-sse.txt >&2 || true
  fail "SSE stream through the proxy produced no event frames"
fi
pass "SSE /api/events streams through the proxy"

docker exec "${NAME}" sh -c '
  test -d /workspace/huggingface &&
  test -d /workspace/models &&
  test -d /workspace/datasets &&
  test -d /workspace/simpletuner/config &&
  test -d /workspace/simpletuner/output &&
  test -d /workspace/simpletuner/.state &&
  test -f /workspace/.stt-layout-version
' || fail "workspace data dirs are missing"
# PID 1 is RunPod /start.sh and does not export these. Read the server process.
# The bracket trick keeps pgrep from matching this shell's own command line.
docker exec "${NAME}" bash -lc '
  pid=$(pgrep -f "[s]impletuner server" | head -n 1)
  test -n "$pid"
  tr "\0" "\n" < /proc/$pid/environ > /tmp/stt-env.txt
  grep -qx "HF_HOME=/workspace/huggingface" /tmp/stt-env.txt
  grep -qx "SIMPLETUNER_CONFIG_DIR=/workspace/simpletuner/config" /tmp/stt-env.txt
  grep -qx "SIMPLETUNER_STATE_DIR=/workspace/simpletuner/.state" /tmp/stt-env.txt
' || fail "SimpleTuner process env is not rooted at /workspace"
pass "data dirs and SimpleTuner env are under /workspace"

docker exec "${NAME}" sh -c 'echo smoke-marker > /workspace/datasets/smoke-marker.txt'
docker restart "${NAME}" >/dev/null || fail "docker restart failed"
ready=0
for _ in $(seq 1 "${READY_TIMEOUT}"); do
  auth="$(curl -s -o /dev/null -u "${WEB_USERNAME}:${WEB_PASSWORD}" -w '%{http_code}' "http://127.0.0.1:${GUI_HOST_PORT}/web/trainer" || true)"
  if [[ "${auth}" == "200" ]]; then
    ready=1
    break
  fi
  sleep 1
done
[[ "${ready}" == "1" ]] || fail "GUI did not return after container restart"
marker="$(docker exec "${NAME}" cat /workspace/datasets/smoke-marker.txt 2>/dev/null || true)"
[[ "${marker}" == "smoke-marker" ]] || fail "workspace marker missing after restart (got ${marker:-empty})"
docker exec "${NAME}" test -f /workspace/.stt-layout-version || fail "layout version missing after restart"
pass "container restart keeps /workspace data"

echo "Starting a container with WEB_PASSWORD unset"
docker run -d --name "${CLOSED_NAME}" \
  -p "127.0.0.1:${CLOSED_HOST_PORT}:8001" \
  "${IMAGE}" >/dev/null || fail "closed-container docker run failed"
closed_ok=0
for _ in $(seq 1 60); do
  if docker logs "${CLOSED_NAME}" 2>&1 | grep -q 'forcing exit 0'; then
    closed_ok=1
    break
  fi
  if ! docker inspect -f '{{.State.Running}}' "${CLOSED_NAME}" | grep -qx true; then
    fail "container without WEB_PASSWORD exited"
  fi
  sleep 1
done
[[ "${closed_ok}" == "1" ]] || fail "start script did not finish gracefully without WEB_PASSWORD"
if ! docker inspect -f '{{.State.Running}}' "${CLOSED_NAME}" | grep -qx true; then
  fail "container without WEB_PASSWORD is not still running"
fi
body="$(curl -fsS "http://127.0.0.1:${CLOSED_HOST_PORT}/" || true)"
if grep -q 'SimpleTuner Training Studio' <<<"${body}"; then
  fail "GUI was exposed without WEB_PASSWORD"
fi
if ! grep -q 'STT_PASSWORD_REQUIRED' <<<"${body}"; then
  echo "----- closed body -----" >&2
  echo "${body}" >&2
  fail "password-missing page was not served"
fi
docker exec "${CLOSED_NAME}" bash -lc 'curl -sf -o /dev/null http://127.0.0.1:18001/web/trainer' \
  && fail "SimpleTuner is listening even though WEB_PASSWORD is unset" \
  || true
pass "WEB_PASSWORD missing: start script exits 0, container stays up, GUI is not exposed"

echo
echo "==== summary ===="
echo "image=${IMAGE} variant=${VARIANT}"
echo "ALL CHECKS PASSED"
