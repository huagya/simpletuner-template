#!/bin/bash
# RunPod /start.sh calls this before SSH setup. It must succeed.
# Real startup is /post_start.sh so it runs after RunPod exports env vars.
set +e
mkdir -p /workspace 2>/dev/null || true
exit 0
