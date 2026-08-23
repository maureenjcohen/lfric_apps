# lfric_dev container

Development image for LFRic-Venus (plan WP6), mirroring the `vpcm_dev`
workflow: the stack is baked into the image, the code is bind-mounted.

## Stack

| Component | Version | Source |
|---|---|---|
| gfortran / g++ | 13.x | Ubuntu 24.04 apt |
| MPICH | 4.2.x | apt (matches Met Office stack choice) |
| HDF5 / NetCDF-C / NetCDF-Fortran | 1.10.x / 4.9.2 / 4.6.1 | apt — versions match LFRic `software_dependencies.rst` |
| PSyclone | 3.3.1 (pinned) | pip |
| rose_picker | HEAD | github.com/MetOffice/rose_picker |
| YAXT | 0.11.0, `--with-idxtype=long` (LFRic halo indices are int64) | gitlab.dkrz.de/dkrz-sw/yaxt |
| pFUnit (+gFTL, fArgParse) | 4.12.0 | Goddard-Fortran-Ecosystem |
| XIOS2 | **r2904** (donor: `vpcm_dev` image, copy-only stage) | IPSL forge SVN was unreachable at build time; LFRic pins r2701 — revert to a direct `svn checkout -r 2701` of `XIOS2/trunk` when the forge is back |

NetCDF is serial: use XIOS `multiple_file` mode. A parallel-HDF5 variant can
follow for the cluster image if `one_file` output is needed.

The `vpcm_dev` image must be present locally (`docker pull maureenjcohen/vpcm_dev`)
— it donates the XIOS source tree in a copy-only stage; none of its x86 code runs.

## Build

```bash
cd venus/container
docker build -t lfric_dev .                      # native arch (aarch64 laptop)
docker buildx build --platform linux/amd64 -t lfric_dev:amd64 .   # cluster arch
```

The recipe has no arch-specific paths — the same file serves both. Native
aarch64 builds are for fast local iteration; the x86-64 image is what runs
under podman on the cluster (and under QEMU on the laptop when bit-faithful
comparison against cluster output matters — the vpcm_dev precedent).

## Run

```bash
docker run -it --rm \
  -v ~/repos/lfric_core:/lfric/core \
  -v ~/repos/lfric_apps:/lfric/apps \
  lfric_dev:latest
```

Inside (login shell sources `/etc/profile.d/lfric.sh`, which sets
`FC/FPP/LDMPI/FFLAGS/LDFLAGS` for the LFRic make build):

```bash
cd /lfric/apps/applications/gungho_model
make build CORE_ROOT_DIR=/lfric/core APPS_ROOT_DIR=/lfric/apps
```

or via the wrapper, which reads `dependencies.yaml`:

```bash
cd /lfric/apps && python3 build/local_build.py -p gungho_model
```
