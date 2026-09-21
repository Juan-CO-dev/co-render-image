# CO render image: Blender 5.2.1 LTS (pinned by sha256) + ffmpeg + sshd, nothing else. Public, no assets, no secrets.
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
# exactly the libraries pod_bootstrap.sh installs on a bare pod, plus sshd and the download tools
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ffmpeg libxi6 libxrender1 libxkbcommon0 libsm6 libgl1 \
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
COPY start.sh /start.sh
RUN chmod 755 /start.sh
EXPOSE 22
CMD ["/start.sh"]
