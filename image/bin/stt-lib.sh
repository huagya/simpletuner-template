# Shared helpers. Sourced, not executed.
# shellcheck shell=bash

stt_workspace() {
  printf '%s\n' "${STT_WORKSPACE_ROOT:-/workspace}"
}

stt_hf_home() {
  if [[ -n "${HF_HOME:-}" ]]; then
    printf '%s\n' "${HF_HOME}"
  else
    printf '%s/huggingface\n' "$(stt_workspace)"
  fi
}

stt_die() {
  echo "ERROR / エラー: $*" >&2
  exit 1
}

stt_say() {
  echo "$*"
}

stt_free_bytes() {
  local path="$1"
  local probe="$path"
  while [[ ! -e "$probe" && "$probe" != "/" ]]; do
    probe="$(dirname "$probe")"
  done
  df -B1 --output=avail "$probe" | awk 'NR==2 {print $1}'
}

# Human sizes from `hf download --dry-run` use decimal units (1.0K = 1000).
stt_parse_size() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import sys
text = sys.argv[1].strip()
if not text or text.lower().startswith("unknown"):
    raise SystemExit(2)
num = ""
unit = ""
for ch in text:
    if ch.isdigit() or ch == ".":
        num += ch
    elif ch.isalpha():
        unit += ch
if not num:
    raise SystemExit(2)
value = float(num)
scale = {"": 1, "K": 1000, "M": 1000**2, "G": 1000**3, "T": 1000**4}
unit = unit.upper()[:1]
if unit not in scale:
    raise SystemExit(2)
print(int(value * scale[unit]))
PY
}

stt_require_space() {
  local path="$1"
  local need="$2"
  local avail
  avail="$(stt_free_bytes "$path")"
  if [[ -z "$avail" || ! "$avail" =~ ^[0-9]+$ ]]; then
    stt_die "空き容量を確認できません / could not read free disk space for ${path}"
  fi
  if (( avail < need )); then
    echo "空き容量が足りません / Not enough free disk space." >&2
    echo "  必要 / need: ${need} bytes" >&2
    echo "  空き / free: ${avail} bytes" >&2
    echo "  場所 / path: ${path}" >&2
    echo "空けるには / to free space:" >&2
    echo "  rm -rf $(stt_workspace)/simpletuner/output/*" >&2
    echo "  hf cache prune" >&2
    exit 1
  fi
}

stt_repo_ok() {
  local repo="$1"
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || stt_die "repo id の形式が違います / bad repo id: ${repo}"
}

stt_gated_hint() {
  local repo="$1"
  local kind="${2:-model}"
  local url
  if [[ "$kind" == "dataset" ]]; then
    url="https://huggingface.co/datasets/${repo}"
  else
    url="https://huggingface.co/${repo}"
  fi
  if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "HF_TOKEN がありません。ゲート付きリポジトリはダウンロードできません。" >&2
    echo "HF_TOKEN is missing, so a gated repository cannot be downloaded." >&2
  else
    echo "HF_TOKEN は設定されていますが、拒否されました（トークンは表示しません）。" >&2
    echo "HF_TOKEN is set but was denied. The token is not printed." >&2
  fi
  echo "Hugging Face のモデルページでライセンスに同意し、HF_TOKEN を設定してください。" >&2
  echo "Accept the license on the Hugging Face page and set HF_TOKEN." >&2
  echo "  ${url}" >&2
}

stt_is_gated_text() {
  local text="$1"
  grep -Eiq '401|403|gated|restricted|unauthorized|access denied|invalid user token|forbidden' <<<"$text"
}
