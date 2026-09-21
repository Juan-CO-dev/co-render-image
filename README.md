# co-render-image

The Compliments Only render image: Blender 5.2.1 LTS (sha-pinned at `/opt/blender`) + ffmpeg + sshd on `ubuntu:22.04`. Public, Blender and libraries only, no assets, no secrets.

Built by GitHub Actions on every `5.*` tag and pushed to `ghcr.io/juan-co-dev/co-blender:<tag>`. The tag is the image version (`5.2.1-1`, `5.2.1-2`, …); there is no `latest`. Nothing is built on a desktop.

Source of truth for these files is the CO-CHIEF vault (`04-AGENTS/tools/render/image/`); changes are authored and reviewed there first, then copied here and tagged. Design: the vault's `03-PROJECTS/marketing/blender-program/stage-a-design.md`, section 2.
