# SimpleTuner image.
#
# The base is nvidia/cuda:12.8.1-base (digest-pinned). It is the small CUDA
# image: driver compatibility libraries, not the devel toolkit. Torch's
# cu128 wheel brings its own nvidia-* libraries. RunPod's base was 12.7GB
# uncompressed and duplicated those libraries; see HANDOFF.md.
#
# Default (GPU):
#   docker build -t stt-runpod:cu128 .
# CPU smoke:
#   docker build --build-arg TORCH_VARIANT=cpu -t stt-runpod:smoke-cpu .

ARG CUDA_BASE_IMAGE=nvidia/cuda:12.8.1-base-ubuntu24.04@sha256:e711c99333fdfe8ae1e677b4972be6c5021f0128a1d31f775c7e58d88921b6a9
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.23@sha256:61d393e44e249f2e4b526b6c7ddcecce245946826e608e11c93ad4f5bba55b21

FROM ${UV_IMAGE} AS uv

FROM ${CUDA_BASE_IMAGE}

ARG TORCH_VARIANT=cu128
ARG CADDY_VERSION=2.11.7
ARG CADDY_SHA512=a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_CACHE_DIR=/root/.cache/uv \
    PIP_CACHE_DIR=/root/.cache/pip \
    PATH="/opt/stt/bin:/opt/stt/venv/bin:${PATH}" \
    STT_TORCH_VARIANT=${TORCH_VARIANT} \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

COPY --from=uv /uv /uvx /bin/

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      python3 \
      python3-venv \
      openssh-server \
      curl \
      ca-certificates \
      libgomp1 \
      libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/run/sshd /opt/stt/bin /opt/stt/share/no-password /opt/stt/locks /opt/stt/run \
 && printf '%s\n' \
      'PasswordAuthentication no' \
      'KbdInteractiveAuthentication no' \
      'PermitRootLogin prohibit-password' \
      > /etc/ssh/sshd_config.d/stt.conf

COPY locks/cpu.txt locks/cu128.txt locks/jupyter.txt /opt/stt/locks/

RUN curl -fsSL -o /tmp/caddy.tar.gz \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
 && echo "${CADDY_SHA512}  /tmp/caddy.tar.gz" | sha512sum -c - \
 && tar -C /opt/stt/bin -xzf /tmp/caddy.tar.gz caddy \
 && chmod 755 /opt/stt/bin/caddy \
 && rm -f /tmp/caddy.tar.gz \
 && /opt/stt/bin/caddy version

# Cache stays on the BuildKit mount. The old image wrote it to
# /workspace/.cache/uv because runpod/base sets UV_CACHE_DIR there.
# deepspeed's sdist needs a compiler. It is purged before the layer is committed.
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked <<'EOS'
set -eux
apt-get update
apt-get install -y --no-install-recommends build-essential python3-dev
case "${TORCH_VARIANT}" in
  cpu) TORCH_INDEX="https://download.pytorch.org/whl/cpu" ;;
  cu128) TORCH_INDEX="https://download.pytorch.org/whl/cu128" ;;
  *) echo "unsupported TORCH_VARIANT=${TORCH_VARIANT}" >&2; exit 1 ;;
esac
test -f "/opt/stt/locks/${TORCH_VARIANT}.txt"
uv venv --python /usr/bin/python3 /opt/stt/venv
uv pip sync \
  --python /opt/stt/venv/bin/python \
  --link-mode copy \
  --index-strategy unsafe-best-match \
  --extra-index-url "${TORCH_INDEX}" \
  "/opt/stt/locks/${TORCH_VARIANT}.txt"
uv pip install \
  --python /opt/stt/venv/bin/python \
  --link-mode copy \
  --require-hashes \
  -r /opt/stt/locks/jupyter.txt
/opt/stt/venv/bin/python - <<'PY'
import json
from pathlib import Path
import simpletuner
import torch
info = {
    "simpletuner": simpletuner.__version__,
    "torch": torch.__version__,
    "torch_cuda": getattr(torch.version, "cuda", None),
}
Path("/opt/stt/build-info.json").write_text(json.dumps(info, indent=2) + "\n")
print(info)
PY
apt-get purge -y build-essential python3-dev
apt-get autoremove -y
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /workspace/.cache /tmp/*
test ! -d /workspace/.cache/uv
EOS

COPY image/stt-start /opt/stt/bin/stt-start
COPY image/jupyter_server_config.py /opt/stt/share/jupyter_server_config.py
COPY image/no-password/index.html /opt/stt/share/no-password/index.html
COPY image/pre_start.sh /pre_start.sh
COPY image/post_start.sh /post_start.sh
COPY image/start.sh /start.sh

RUN chmod 755 /opt/stt/bin/stt-start /pre_start.sh /post_start.sh /start.sh

# The CUDA image's entrypoint injects the host driver libraries, then execs
# this command. A plain `docker run` on Windows uses the same path.
CMD ["/start.sh"]
