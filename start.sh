#!/usr/bin/env bash
# Container entrypoint for the CO render image on Runpod: install the pod's public key (Runpod injects PUBLIC_KEY when
# the pod is created with startSsh / the PUBLIC_KEY env), start sshd, then idle. The render itself is driven over SSH
# by gpu_render.py exactly as before; nothing renders on boot.
set -euo pipefail
if [ -n "${PUBLIC_KEY:-}" ]; then
  mkdir -p /root/.ssh
  echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/authorized_keys
fi
/usr/sbin/sshd
echo "co-blender image ready: $(/opt/blender/blender -b --version | head -1)"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null || echo "no nvidia-smi"
exec sleep infinity
