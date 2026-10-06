#!/bin/bash
# RunPod /start.sh uses `set -e`. A failing hook kills the pod before
# `sleep infinity`, which leaves a non-programmer with nothing to debug.
# This hook always exits 0. stt-start also exits 0.
set +e
if [[ -x /opt/stt/bin/stt-start ]]; then
  /opt/stt/bin/stt-start
  status=$?
else
  echo "[post_start] /opt/stt/bin/stt-start is missing"
  status=127
fi
echo "[post_start] stt-start returned ${status}; forcing exit 0 so the pod stays up / 失敗してもポッドは落とさない"
exit 0
