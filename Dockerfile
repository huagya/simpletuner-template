# RunPod image for SimpleTuner. The default build installs torch 2.11.0+cu128.
# A CPU smoke build is:
#   docker build --build-arg TORCH_VARIANT=cpu -t stt-runpod:smoke .
#
# The base tag is digest-pinned (versions.env). Local Docker Desktop can run
# this same image: RunPod variables are optional, and /start.sh is still PID 1.

ARG RUNPOD_BASE_IMAGE=runpod/base:1.4.0-cuda1281-ubuntu2404@sha256:e6eb5a38bd3b321f41e7c584334c9ebc15e1e529574c7f2c866d148990cfb817
FROM ${RUNPOD_BASE_IMAGE}

ARG TORCH_VARIANT=cu128
ARG CADDY_VERSION=2.11.7
ARG CADDY_SHA512=a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    PATH="/opt/stt/bin:/opt/stt/venv/bin:${PATH}" \
    STT_TORCH_VARIANT=${TORCH_VARIANT}

RUN mkdir -p /opt/stt/bin /opt/stt/share/no-password /opt/stt/locks /opt/stt/run

COPY locks/cpu.txt locks/cu128.txt /opt/stt/locks/

RUN curl -fsSL -o /tmp/caddy.tar.gz \
      "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" \
 && echo "${CADDY_SHA512}  /tmp/caddy.tar.gz" | sha512sum -c - \
 && tar -C /opt/stt/bin -xzf /tmp/caddy.tar.gz caddy \
 && chmod 755 /opt/stt/bin/caddy \
 && rm -f /tmp/caddy.tar.gz \
 && /opt/stt/bin/caddy version

# Dependencies are synced here. Container start must not run pip.
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    set -eux; \
    case "${TORCH_VARIANT}" in \
      cpu) TORCH_INDEX="https://download.pytorch.org/whl/cpu" ;; \
      cu128) TORCH_INDEX="https://download.pytorch.org/whl/cu128" ;; \
      *) echo "unsupported TORCH_VARIANT=${TORCH_VARIANT}" >&2; exit 1 ;; \
    esac; \
    test -f "/opt/stt/locks/${TORCH_VARIANT}.txt"; \
    uv venv --python /usr/bin/python3.12 /opt/stt/venv; \
    uv pip sync \
      --python /opt/stt/venv/bin/python \
      --link-mode copy \
      --index-strategy unsafe-best-match \
      --extra-index-url "${TORCH_INDEX}" \
      "/opt/stt/locks/${TORCH_VARIANT}.txt"; \
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

COPY image/stt-start /opt/stt/bin/stt-start
COPY image/jupyter_server_config.py /opt/stt/share/jupyter_server_config.py
COPY image/no-password/index.html /opt/stt/share/no-password/index.html
COPY image/pre_start.sh /pre_start.sh
COPY image/post_start.sh /post_start.sh

RUN chmod 755 /opt/stt/bin/stt-start /pre_start.sh /post_start.sh \
 && rm -rf /root/.cache/pip /tmp/* || true

# RunPod's /start.sh calls /pre_start.sh and /post_start.sh, then sleeps.
# Do not replace CMD. A plain `docker run` on Windows uses the same path.
CMD ["/start.sh"]
