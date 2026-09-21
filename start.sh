#!/usr/bin/env bash
# Container entrypoint for the CO render image on Runpod (5.2.1-2, CC ruling 2026-09-21 after the 5.2.1-1 proof pod):
# host keys in case /etc/ssh is shadowed, then sshd in the FOREGROUND with logging to stderr so the reason for any
# dropped connection lands in the container log (stream-pod-logs), then the proof lines, then wait on sshd.
# Runpod injects PUBLIC_KEY when the pod is created with it in env; the render is driven over SSH by gpu_render.py.
set -euo pipefail
ssh-keygen -A >/dev/null 2>&1 || true
if [ -n "${PUBLIC_KEY:-}" ]; then
  mkdir -p /root/.ssh
  echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/authorized_keys
fi
mkdir -p /run/sshd
/usr/sbin/sshd -D -e &
SSHD_PID=$!
echo "co-blender image ready: $(/opt/blender/blender -b --version | head -1)"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null || echo "no nvidia-smi"
wait "$SSHD_PID"
