#!/usr/bin/env bash
# Offline tests for the helper commands and stt-doctor.
# Fake hf, wget, curl, git, df, nvidia-smi, and torch stand in for the network and the GPU.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${STT_BIN:-${ROOT}/image/bin}"
if [[ "${STT_REQUIRE_IMAGE_BIN:-}" == "1" ]]; then
  BIN=/opt/stt/bin
fi
export PATH="${BIN}:${PATH}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  echo "PASS: $*"
}

[[ -x "${BIN}/hf-model" ]] || fail "hf-model is not executable at ${BIN}/hf-model"
[[ -x "${BIN}/stt-doctor" ]] || fail "stt-doctor is not executable at ${BIN}/stt-doctor"
if [[ "${STT_REQUIRE_IMAGE_BIN:-}" == "1" ]]; then
  [[ "$(command -v hf-model)" == /opt/stt/bin/hf-model ]] || fail "hf-model is not the image copy"
  [[ "$(command -v stt-doctor)" == /opt/stt/bin/stt-doctor ]] || fail "stt-doctor is not the image copy"
fi

TOKEN="hf_FAKESECRETTOKENVALUE1234567890"
PASSWORD="ci-password-123456"

setup_mocks() {
  MOCK="$(mktemp -d)"
  LOG="${MOCK}/log"
  : >"$LOG"
  cat >"${MOCK}/hf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STT_MOCK_LOG}"
printf 'HF_HOME=%s\n' "${HF_HOME-}" >> "${STT_MOCK_LOG}"
if [[ "${1:-}" == "auth" ]]; then
  if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "no token" >&2
    exit 1
  fi
  if [[ "${HF_TOKEN}" == *DENIED* ]]; then
    echo "401 Unauthorized" >&2
    exit 1
  fi
  echo "name: tester"
  exit 0
fi
if [[ "${1:-}" == "download" ]]; then
  if [[ "$*" == *"--dry-run"* ]]; then
    if [[ -n "${STT_MOCK_HF_FAIL:-}" ]]; then
      echo "${STT_MOCK_HF_FAIL}" >&2
      exit 1
    fi
    echo "[dry-run] Will download 1 files (out of 1) totalling ${STT_MOCK_HF_SIZE:-1.0M}."
    exit 0
  fi
  printf 'REAL_DOWNLOAD %s\n' "$*" >> "${STT_MOCK_LOG}"
  exit 0
fi
echo "unexpected hf args" >&2
exit 1
EOF
  cat >"${MOCK}/wget" <<'EOF'
#!/usr/bin/env bash
printf 'WGET %s\n' "$*" >> "${STT_MOCK_LOG}"
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-O" ]]; then
    out="$arg"
  fi
  prev="$arg"
done
if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  echo downloaded > "$out"
fi
exit 0
EOF
  cat >"${MOCK}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'CURL %s\n' "$*" >> "${STT_MOCK_LOG}"
joined="$*"
  if [[ "$joined" == *"-fsSI"* || "$joined" == *" -I "* || "$joined" == *"--head"* ]]; then
  if [[ -n "${STT_MOCK_CURL_FAIL:-}" ]]; then
    echo "${STT_MOCK_CURL_FAIL}" >&2
    exit 22
  fi
  echo "HTTP/1.1 200"
  echo "content-length: ${STT_MOCK_URL_BYTES:-1000}"
  exit 0
fi
if [[ "$joined" == *":18001"* ]]; then
  echo 200
  exit 0
fi
if [[ "$joined" == *"-u "* ]]; then
  echo 200
  exit 0
fi
echo 401
exit 0
EOF
  cat >"${MOCK}/git" <<'EOF'
#!/usr/bin/env bash
printf 'GIT %s\n' "$*" >> "${STT_MOCK_LOG}"
if [[ "${1:-}" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest"
fi
exit 0
EOF
  cat >"${MOCK}/git-lfs" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"${MOCK}/df" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *avail* ]]; then
  echo Avail
  echo "${STT_MOCK_AVAIL:-999999999999}"
  exit 0
fi
if [[ "$*" == *"--output=size"* ]]; then
  echo Size
  echo "${STT_MOCK_SHM:-2147483648}"
  exit 0
fi
if [[ "$*" == *"-P"* ]]; then
  echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
  echo "/dev/mockdisk 1 1 1 1 ${STT_WORKSPACE_ROOT:-/workspace}"
  exit 0
fi
echo "Filesystem Size Used Avail Use% Mounted on"
echo "mock 100G 1G 99G 1% /"
EOF
  cat >"${MOCK}/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
if [[ "${STT_MOCK_GPU:-yes}" == "missing" ]]; then
  echo "no nvidia-smi" >&2
  exit 127
fi
if [[ "$*" == *"-L"* ]]; then
  if [[ "${STT_MOCK_GPU:-yes}" == "none" ]]; then
    echo "No devices found" >&2
    exit 1
  fi
  echo "GPU 0: NVIDIA Mock GPU (UUID: GPU-mock)"
  exit 0
fi
if [[ "$*" == *"memory.free"* ]]; then
  echo "${STT_MOCK_FREE_MIB:-16000}, ${STT_MOCK_TOTAL_MIB:-16000}"
  exit 0
fi
if [[ "$*" == *"driver_version"* ]]; then
  echo "${STT_MOCK_DRIVER:-580.00}"
  exit 0
fi
echo "Driver Version                            : ${STT_MOCK_DRIVER:-580.00}"
exit 0
EOF
  cat >"${MOCK}/python3" <<'EOF'
#!/usr/bin/env bash
real="/usr/bin/python3"
if [[ "${1:-}" == "-" ]]; then
  body="$(cat)"
  if [[ "$body" == *"import torch"* ]]; then
    if [[ "${STT_MOCK_TORCH_CUDA:-0}" == "1" ]]; then
      echo '{"ok":true,"cuda":true,"version":"2.11.0+cu128","cuda_ver":"12.8","name":"Mock GPU","vram":17179869184,"error":null}'
    else
      echo '{"ok":true,"cuda":false,"version":"2.11.0+cpu","cuda_ver":null,"name":null,"vram":null,"error":null}'
    fi
    exit 0
  fi
  printf '%s' "$body" | "$real" - "${@:2}"
  exit $?
fi
exec "$real" "$@"
EOF
  chmod 755 "${MOCK}/hf" "${MOCK}/wget" "${MOCK}/curl" "${MOCK}/git" "${MOCK}/git-lfs" "${MOCK}/df" "${MOCK}/nvidia-smi" "${MOCK}/python3"
  export STT_MOCK_LOG="$LOG"
  export PATH="${MOCK}:${BIN}:${PATH}"
  export STT_WORKSPACE_ROOT="${MOCK}/workspace"
  mkdir -p "${STT_WORKSPACE_ROOT}"
  unset HF_HOME HF_HUB_CACHE || true
  unset STT_MOCK_HF_FAIL STT_MOCK_CURL_FAIL || true
  export STT_MOCK_AVAIL=999999999999
  export STT_MOCK_SHM=2147483648
  export STT_MOCK_GPU=yes
  export STT_MOCK_DRIVER=580.00
  export STT_MOCK_TORCH_CUDA=0
  export STT_MOCK_HF_SIZE=1.0M
  export HF_TOKEN="$TOKEN"
  export WEB_PASSWORD="$PASSWORD"
  export WEB_USERNAME=admin
}

assert_absent() {
  local file="$1"
  if grep -F "$TOKEN" "$file" >/dev/null 2>&1; then
    fail "HF_TOKEN leaked in $file"
  fi
  if grep -F "$PASSWORD" "$file" >/dev/null 2>&1; then
    fail "WEB_PASSWORD leaked in $file"
  fi
}

zip_has_no_secrets() {
  local zip="$1"
  [[ -f "$zip" ]] || fail "zip missing: $zip"
  python3 - "$zip" "$TOKEN" "$PASSWORD" <<'PY'
import sys, zipfile
zpath, token, password = sys.argv[1:]
with zipfile.ZipFile(zpath) as zf:
    names = zf.namelist()
    if "doctor.json" not in names or "env.txt" not in names:
        raise SystemExit("zip is missing doctor.json or env.txt")
    blob = "\n".join(zf.read(name).decode("utf-8", errors="replace") for name in names)
if token in blob or password in blob:
    raise SystemExit("secret leaked into the zip")
if "***redacted(len=" not in blob:
    raise SystemExit("redaction marker missing")
print("zip-ok", len(names))
PY
}

setup_mocks
out="$(hf-model PixArt-alpha/PixArt-Sigma-XL-2-1024-MS 2>&1)" || fail "hf-model happy path failed: ${out}"
grep -F "HF_HOME=${STT_WORKSPACE_ROOT}/huggingface" "$LOG" >/dev/null || fail "HF_HOME was not the workspace cache"
grep -F "REAL_DOWNLOAD" "$LOG" >/dev/null || fail "hf download was not called"
grep -F "PixArt-alpha/PixArt-Sigma-XL-2-1024-MS" "$LOG" >/dev/null || fail "repo was not passed to hf"
grep -F -- "--local-dir" "$LOG" >/dev/null && fail "default hf-model should stay in the HF cache"
assert_absent <(printf '%s' "$out")
pass "hf-model downloads into the HF cache"

: >"$LOG"
out="$(hf-model PixArt-alpha/PixArt-Sigma-XL-2-1024-MS --to sigma 2>&1)" || fail "hf-model --to failed: ${out}"
grep -F "REAL_DOWNLOAD" "$LOG" >/dev/null || fail "hf-model --to did not download"
grep -F -- "--local-dir ${STT_WORKSPACE_ROOT}/models/sigma" "$LOG" >/dev/null \
  || fail "hf-model --to did not use models/: $(cat "$LOG")"
pass "hf-model --to writes under models/"

: >"$LOG"
export STT_MOCK_AVAIL=1000
set +e
out="$(hf-model PixArt-alpha/PixArt-Sigma-XL-2-1024-MS 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "low disk hf-model exited 0"
grep -F "空き容量が足りません" <<<"$out" >/dev/null || fail "low disk message missing"
grep -F "REAL_DOWNLOAD" "$LOG" >/dev/null && fail "low disk still downloaded"
pass "hf-model refuses when disk is short"

: >"$LOG"
unset HF_TOKEN
export STT_MOCK_AVAIL=999999999999
export STT_MOCK_HF_FAIL="403 Forbidden"
set +e
out="$(hf-model PixArt-alpha/PixArt-Sigma-XL-2-1024-MS 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "gated hf-model exited 0"
grep -F "ライセンスに同意" <<<"$out" >/dev/null || fail "gated hint missing"
grep -F "HF_TOKEN がありません" <<<"$out" >/dev/null || fail "missing-token hint missing"
grep -F "https://huggingface.co/PixArt-alpha/PixArt-Sigma-XL-2-1024-MS" <<<"$out" >/dev/null || fail "repo URL missing"
pass "hf-model explains a missing token for a gated repo"

export HF_TOKEN="$TOKEN"
export STT_MOCK_HF_FAIL="401 Unauthorized"
set +e
out="$(hf-dataset org/private-set captions --include '*.txt' 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "denied dataset exited 0"
grep -F "拒否されました" <<<"$out" >/dev/null || fail "denied hint missing"
grep -F "$TOKEN" <<<"$out" >/dev/null && fail "token printed on denial"
grep -F "https://huggingface.co/datasets/org/private-set" <<<"$out" >/dev/null || fail "dataset URL missing"
pass "hf-dataset reports a denied token without printing it"

unset STT_MOCK_HF_FAIL
: >"$LOG"
out="$(hf-dataset org/public-set captions --include '*.txt' 2>&1)" || fail "hf-dataset failed: ${out}"
grep -F "REAL_DOWNLOAD" "$LOG" >/dev/null || fail "hf-dataset did not download"
grep -F -- "--repo-type dataset" "$LOG" >/dev/null || fail "dataset repo type missing"
grep -F -- "--local-dir ${STT_WORKSPACE_ROOT}/datasets/captions" "$LOG" >/dev/null || fail "dataset dir missing: $(cat "$LOG")"
grep -F -- "--include *.txt" "$LOG" >/dev/null || fail "include pattern missing"
pass "hf-dataset saves under datasets/"

: >"$LOG"
out="$(get-url "https://example.com/images.zip" "${STT_WORKSPACE_ROOT}/datasets" 2>&1)" || fail "get-url failed: ${out}"
grep -F "WGET" "$LOG" >/dev/null || fail "wget was not called"
grep -F "Authorization" "$LOG" >/dev/null && fail "non-HF URL got an Authorization header"
grep -F "$TOKEN" <<<"$out" >/dev/null && fail "token printed by get-url"
pass "get-url does not send the HF token to other hosts"

: >"$LOG"
out="$(get-url "https://huggingface.co/PixArt-alpha/PixArt-Sigma-XL-2-1024-MS/resolve/main/model.safetensors" 2>&1)" \
  || fail "get-url HF failed: ${out}"
grep -F "Authorization: Bearer ${TOKEN}" "$LOG" >/dev/null || fail "HF URL did not get the bearer header"
grep -F "$TOKEN" <<<"$out" >/dev/null && fail "token printed for an HF URL"
pass "get-url sends the token only to huggingface.co"

: >"$LOG"
export STT_MOCK_AVAIL=10
export STT_MOCK_URL_BYTES=5000000
set +e
out="$(get-url "https://example.com/big.bin" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "low disk get-url exited 0"
grep -F "WGET" "$LOG" >/dev/null && fail "low disk get-url still called wget"
pass "get-url refuses when disk is short"

export STT_MOCK_AVAIL=999999999999
: >"$LOG"
out="$(git-clone-hf PixArt-alpha/PixArt-Sigma-XL-2-1024-MS 2>&1)" || fail "git-clone-hf failed: ${out}"
grep -F "2 倍" <<<"$out" >/dev/null || fail "git-lfs double-copy warning missing"
grep -F "hf-model" <<<"$out" >/dev/null || fail "git-clone-hf did not recommend hf-model"
grep -F "GIT clone https://huggingface.co/PixArt-alpha/PixArt-Sigma-XL-2-1024-MS" "$LOG" >/dev/null \
  || fail "git clone URL was wrong: $(cat "$LOG")"
grep -F "$TOKEN" <<<"$out" >/dev/null && fail "token printed by git-clone-hf"
grep -F "$TOKEN" "$LOG" >/dev/null && fail "token stored in the git mock log"
pass "git-clone-hf warns and does not put the token in the URL"

help_out="$(stt-help)"
grep -F "PixArt-alpha/PixArt-Sigma-XL-2-1024-MS" <<<"$help_out" >/dev/null || fail "help missing PixArt Sigma"
grep -F "stabilityai/stable-cascade" <<<"$help_out" >/dev/null || fail "help missing Stable Cascade"
grep -F "stt-doctor" <<<"$help_out" >/dev/null || fail "help missing stt-doctor"
grep -F "困ったら" <<<"$help_out" >/dev/null || fail "help is not Japanese"
pass "stt-help lists PixArt Sigma and Stable Cascade"

export STT_MOCK_GPU=none
export STT_MOCK_TORCH_CUDA=0
set +e
doc="$(stt-doctor --json --zip 2>"${MOCK}/doctor.err")"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "doctor with no GPU exited 0"
python3 - "$doc" <<'PY' || fail "G01 was not FAIL"
import json, sys
checks = {row["id"]: row["status"] for row in json.loads(sys.argv[1])["checks"]}
assert checks["G01"] == "FAIL", checks
assert checks["G02"] == "SKIP", checks
PY
zip_path="$(sed -n 's/^診断ファイル \/ diagnostic zip: //p' "${MOCK}/doctor.err" | tail -n 1)"
zip_has_no_secrets "$zip_path"
pass "stt-doctor reports no GPU and redacts the zip"

export STT_MOCK_GPU=yes
export STT_MOCK_DRIVER=550.54
export STT_MOCK_TORCH_CUDA=1
set +e
doc="$(stt-doctor --json 2>/dev/null)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "old driver doctor exited 0"
python3 - "$doc" <<'PY' || fail "G02 was not FAIL"
import json, sys
checks = {row["id"]: row for row in json.loads(sys.argv[1])["checks"]}
assert checks["G02"]["status"] == "FAIL", checks["G02"]
assert "570" in checks["G02"]["hint"] or "12.8" in checks["G02"]["hint"]
PY
pass "stt-doctor flags a driver older than 570"

export STT_MOCK_DRIVER=580.76.05
export STT_MOCK_TORCH_CUDA=1
export HF_TOKEN="$TOKEN"
doc="$(stt-doctor --json --zip 2>"${MOCK}/doctor-ok.err")" || fail "healthy doctor failed"
python3 - "$doc" <<'PY' || fail "healthy doctor statuses were wrong"
import json, sys
checks = {row["id"]: row["status"] for row in json.loads(sys.argv[1])["checks"]}
for key in ("G01", "G02", "G03", "G04", "S01", "S02", "S03", "A01", "H01"):
    assert checks[key] == "PASS", (key, checks[key], checks)
PY
grep -F "Mock GPU" <<<"$doc" >/dev/null || fail "device name missing"
grep -F "$TOKEN" <<<"$doc" >/dev/null && fail "token in doctor json"
grep -F "$PASSWORD" <<<"$doc" >/dev/null && fail "password in doctor json"
zip_path="$(sed -n 's/^診断ファイル \/ diagnostic zip: //p' "${MOCK}/doctor-ok.err" | tail -n 1)"
zip_has_no_secrets "$zip_path"
pass "stt-doctor passes GPU, torch, proxy, and token checks without leaking secrets"

export HF_TOKEN="${TOKEN}DENIED"
set +e
doc="$(stt-doctor --json 2>/dev/null)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "denied token doctor exited 0"
python3 - "$doc" <<'PY' || fail "H01 was not FAIL"
import json, sys
checks = {row["id"]: row for row in json.loads(sys.argv[1])["checks"]}
assert checks["H01"]["status"] == "FAIL", checks["H01"]
PY
grep -F "$TOKEN" <<<"$doc" >/dev/null && fail "denied token was printed"
pass "stt-doctor reports an invalid HF token without printing it"

echo "ALL HELPER TESTS PASSED"
