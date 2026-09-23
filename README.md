# co-render-image

The Compliments Only render image: Blender 5.2.1 LTS (sha-pinned at `/opt/blender`) + ffmpeg + sshd on `ubuntu:22.04`, and from `5.2.1-3` COLMAP 4.2.0 built with CUDA for the dense step of photogrammetry. Public, tools and libraries only, no assets, no secrets.

Built by GitHub Actions on every `5.*` tag and pushed to `ghcr.io/juan-co-dev/co-blender:<tag>`. The tag is the image version (`5.2.1-1`, `5.2.1-2`, `5.2.1-3`, …); there is no `latest`. Nothing is built on a desktop. The workflow smokes the pushed image: Blender version, ffmpeg, `colmap help` must say `with CUDA`, and `open3d` + `trimesh` import.

Source of truth for these files is the CO-CHIEF vault (`04-AGENTS/tools/render/image/`); changes are authored and reviewed there first, then copied here and tagged. Design: the vault's `03-PROJECTS/marketing/blender-program/stage-a-design.md`, section 2.

## What is in the image

| path | what |
|---|---|
| `/opt/blender/blender` (on `PATH`) | Blender 5.2.1 LTS, sha-pinned tarball; ships its own CUDA/OptiX kernels |
| `ffmpeg` | Ubuntu 22.04 package |
| `colmap` (`/usr/local/bin`, wrapper) | COLMAP 4.2.0, conda-forge build `cuda_129ha585b08_0`: CUDA 12.9 runtime inside the prefix, compiled for all CUDA architectures (sm_89 for the 4090), CGAL for `delaunay_mesher`, `mesh_texturer` included. Runs headless (`QT_QPA_PLATFORM=offscreen`) |
| `recon-python` (`/usr/local/bin`, wrapper) | Python 3.11 in the same prefix with `open3d-cpu` 0.19.0, `trimesh` 5.1.0, `pillow` |
| `/opt/conda/envs/recon` | the COLMAP prefix; deliberately **not** on `PATH`, so its python and libraries never shadow the system ones Blender's pipeline uses |
| `/start.sh` | installs Runpod's `PUBLIC_KEY`, runs sshd in the foreground with logging, prints the Blender version and `nvidia-smi` |

**Host driver.** Blender brings its own kernels; COLMAP brings its own CUDA 12.9 runtime. Both need only the host driver, and COLMAP needs it at CUDA 12.9 or newer (driver ≥ 575, the same floor Blender's OptiX already needs). Create pods with `allowedCudaVersions` of `["12.9","13.0","13.2"]` or narrower. For a dense sitting, set `containerDiskInGb` to 30: the image is several GB larger from `5.2.1-3` on, and the dense workspace lives on the container disk unless a network volume is attached.

## COLMAP for our orbit (phone set → sparse → dense → mesh)

The sparse half runs anywhere (the 09-22 set was solved on the laptop CPU with pycolmap 4.2.0). The dense half needs the GPU and is what this image is for. On the pod, with the images in `/workspace/sfm/images`:

```bash
W=/workspace/sfm
# sparse (CPU is fine; --FeatureExtraction.use_gpu 1 / --FeatureMatching.use_gpu 1 on a pod)
colmap feature_extractor  --database_path $W/database.db --image_path $W/images \
                          --ImageReader.single_camera 1 --ImageReader.camera_model SIMPLE_RADIAL
colmap exhaustive_matcher --database_path $W/database.db
mkdir -p $W/sparse
colmap mapper             --database_path $W/database.db --image_path $W/images --output_path $W/sparse
# the mapper can write several sub-models (sparse/0, sparse/1, ...); their numbering is NOT by size. Use the one with
# the most registered images: `colmap model_analyzer --path $W/sparse/<n>` prints it. (09-22: sparse/1, 23 frames.)
M=$W/sparse/1
# dense (GPU)
colmap image_undistorter  --image_path $W/images --input_path $M --output_path $W/dense \
                          --output_type COLMAP --max_image_size 2000
colmap patch_match_stereo --workspace_path $W/dense --workspace_format COLMAP \
                          --PatchMatchStereo.geom_consistency true
colmap stereo_fusion      --workspace_path $W/dense --workspace_format COLMAP --input_type geometric \
                          --output_path $W/dense/fused.ply
colmap poisson_mesher     --input_path $W/dense/fused.ply --output_path $W/dense/meshed-poisson.ply \
                          --PoissonMeshing.depth 11 --PoissonMeshing.trim 7
# optional: visibility-aware mesh (reads dense/fused.ply + fused.ply.vis) and a UV-textured mesh from the photos
colmap delaunay_mesher    --input_path $W/dense --input_type dense --output_path $W/dense/meshed-delaunay.ply
colmap mesh_texturer      --workspace_path $W/dense --input_path <mesh.ply> --output_path $W/dense/textured
```

The images passed to `image_undistorter` must be the ones the sparse model was solved on, **at that resolution**: the intrinsics are in their pixels, and a mismatch produces garbage without an error.

The whole dense half, with that check, model auto-selection, mesh cleanup (largest component, decimation, a PLY in COLMAP's own layout so `mesh_texturer` reads it), `.glb` export, resumable stages and a `recon.json` of counts and seconds, is the vault script `03-PROJECTS/marketing/shoots/dense_recon_pod.sh`:

```bash
bash dense_recon_pod.sh     # /workspace/sfm/{images,sparse/<n>} -> /workspace/out/{fused.ply, mesh.ply, mesh.glb,
                            #   textured/{mesh.ply,texture.png}, mesh_textured.glb, recon.json}
```
