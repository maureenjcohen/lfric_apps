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
| XIOS2 | **r2904** (donor: `vpcm_dev` image, copy-only stage) | IPSL forge SVN was unreachable at build time; LFRic pins r2701 — revert to a direct `svn checkout -r 2701` of `XIOS2/trunk` when the forge is back. `--build-arg XIOS_SRC=git` selects `hiker/xios-2252` instead |

NetCDF is serial: use XIOS `multiple_file` mode. A parallel-HDF5 variant can
follow for the cluster image if `one_file` output is needed.

The `vpcm_dev` image must be present locally (`docker pull maureenjcohen/vpcm_dev`)
— it donates the XIOS source tree in a copy-only stage; none of its x86 code runs.

## Build

```bash
cd venus/container
docker build --platform linux/amd64 -t lfric_dev:amd64 .
```

**Always build x86-64**, on both laptop and cluster: the laptop runs it under QEMU
emulation (slow, but bit-faithful to the cluster — the `vpcm_dev` precedent), the
cluster runs it natively under podman. The recipe does build natively on aarch64,
but the resulting image cannot run the model — do not "fix" this by dropping the
`--platform` flag. See BUG-001 in the bug log (planning folder, path in the
top-level `CLAUDE.md`).

## Run

```bash
docker run -it --rm --ulimit stack=-1 \
  -v ~/repos/lfric_core:/lfric/core \
  -v ~/repos/lfric_apps:/lfric/apps \
  lfric_dev:amd64
```

`dependencies.yaml` keeps its upstream `git@github.com:` URLs; the image
rewrites them to HTTPS via `git config --system url.…insteadOf`, so no SSH
keys are needed and the file stays byte-identical to upstream.

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
