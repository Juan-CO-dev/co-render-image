# CO render image: Blender 5.2.1 LTS (pinned by sha256) + ffmpeg + sshd + COLMAP (CUDA) for dense photogrammetry.
# Public, no assets, no secrets.
# 5.2.1-2 (2026-09-21): sshd config drop-in + foreground sshd with logging (start.sh); Blender unchanged.
# 5.2.1-3 (2026-09-22): COLMAP 4.2.0 CUDA build from conda-forge in its own prefix (/opt/conda/envs/recon), plus
#   open3d-cpu + trimesh for mesh cleanup and .glb export (vertex colour and UV-textured); `colmap` and `recon-python`
#   wrappers on PATH. Blender, ffmpeg, sshd unchanged.
# Built by GitHub Actions in the co-render-image repo (see github-workflow-build.yml beside this file) and pushed to
# ghcr.io/<owner>/co-blender:5.2.1-<n>. Never tagged `latest` (CC ruling 2026-09-19). Design: 03-PROJECTS/marketing/
# blender-program/stage-a-design.md section 2.
#
# Base is plain Ubuntu, not an nvidia/cuda image: Blender ships its own CUDA/OptiX kernels and runtime; only the host
# driver is injected by the container runtime. A cuda>= image label is what crash-looped the 2026-09-06 pods.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    PATH=/opt/blender:$PATH
# exactly the libraries pod_bootstrap.sh installs on a bare pod, plus sshd, the download tools, and libgomp1 (open3d)
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ffmpeg libxi6 libxrender1 libxkbcommon0 libsm6 libgl1 libgomp1 \
      openssh-server curl ca-certificates xz-utils \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /root/.ssh /workspace \
 && chmod 700 /root/.ssh
# the same tarball, sha pin and install path as pod_bootstrap.sh, so gpu_render.POD_BLENDER (/opt/blender/blender)
# is unchanged and the bootstrap script becomes a no-op that prints the version as proof
ARG BLENDER_URL=https://download.blender.org/release/Blender5.2/blender-5.2.1-linux-x64.tar.xz
ARG BLENDER_SHA=a31f524fa99a527d3d52b7f5aaa68c34e1a19d5a1c9473f79c5cc610fd5b10e9
RUN curl -sSL -A "Mozilla/5.0" --connect-timeout 15 --max-time 900 -o /tmp/blender.tar.xz "$BLENDER_URL" \
 && echo "$BLENDER_SHA  /tmp/blender.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/blender \
 && tar xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender \
 && rm /tmp/blender.tar.xz \
 && /opt/blender/blender -b --version | head -1
# COLMAP with CUDA for the dense step (patch_match_stereo, stereo_fusion, poisson_mesher, delaunay_mesher). The Ubuntu
# apt colmap is CPU-only, and the official colmap/colmap image is built on Ubuntu 24.04 (glibc 2.39), so its binary
# will not run on this 22.04 base. conda-forge's build is compiled with CMAKE_CUDA_ARCHITECTURES=all (sm_89 included)
# and CGAL (delaunay_mesher), and brings its own CUDA 12.9 runtime inside the prefix; only the host driver comes from
# Runpod, and it must be CUDA >= 12.9 (driver >= 575, the same floor OptiX already needs). CONDA_OVERRIDE_CUDA lets the
# solver pick the CUDA variant on a GPU-less CI runner. The prefix stays OFF the global PATH so its python/ffmpeg never
# shadow the system ones Blender's pipeline uses; two wrappers expose what the pod scripts need.
ARG MICROMAMBA_URL=https://github.com/mamba-org/micromamba-releases/releases/download/2.9.0-0/micromamba-linux-64
ARG MICROMAMBA_SHA=366cd9cd8be14df1ab8ed50352a82111082a36686b2d389fdb79a92c3fafb3e3
ARG COLMAP_SPEC=colmap=4.2.0=cuda_129ha585b08_0
ARG PIP_SPECS="open3d-cpu==0.19.0 trimesh==5.1.0 pillow==12.3.0"
ENV MAMBA_ROOT_PREFIX=/opt/conda
RUN curl -sSL --connect-timeout 15 --max-time 300 -o /usr/local/bin/micromamba "$MICROMAMBA_URL" \
 && echo "$MICROMAMBA_SHA  /usr/local/bin/micromamba" | sha256sum -c - \
 && chmod 755 /usr/local/bin/micromamba \
 && CONDA_OVERRIDE_CUDA=12.9 micromamba create -y -q -n recon -c conda-forge --override-channels \
      "$COLMAP_SPEC" python=3.11 pip \
 && /opt/conda/envs/recon/bin/pip install --no-cache-dir -q $PIP_SPECS \
 && micromamba clean -a -y -q \
 && printf '#!/bin/sh\nexport QT_QPA_PLATFORM=offscreen\nexec /opt/conda/envs/recon/bin/colmap "$@"\n' \
      > /usr/local/bin/colmap \
 && printf '#!/bin/sh\nexec /opt/conda/envs/recon/bin/python "$@"\n' > /usr/local/bin/recon-python \
 && chmod 755 /usr/local/bin/colmap /usr/local/bin/recon-python \
 && colmap help | head -1 \
 && colmap help | head -1 | grep -q "with CUDA" \
 && recon-python -c "import open3d, trimesh; print('open3d', open3d.__version__, 'trimesh', trimesh.__version__)"
# sshd for a container behind Runpod's proxied port 22 (CC ruling 2026-09-21 after the 5.2.1-1 proof pod dropped an
# 84 MB push): stock Ubuntu sshd marks packets af21/cs1 (OpenSSH >= 7.8) and some overlay paths reset large bulk
# transfers on it; IPQoS cs0 cs0 is the known fix. Keepalives so a 30-minute render is never dropped as idle.
RUN printf '%s\n' \
      'PermitRootLogin prohibit-password' \
      'UseDNS no' \
      'TCPKeepAlive yes' \
      'ClientAliveInterval 30' \
      'ClientAliveCountMax 10' \
      'MaxStartups 30' \
      'IPQoS cs0 cs0' \
      > /etc/ssh/sshd_config.d/co.conf
COPY start.sh /start.sh
RUN chmod 755 /start.sh
EXPOSE 22
CMD ["/start.sh"]
