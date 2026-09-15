# lfric_dev container

Development image for LFRic-Venus, mirroring the `vpcm_dev` workflow: the
stack is baked into the image, the code is bind-mounted.

## Stack

| Component | Version | Source |
|---|---|---|
| gfortran / g++ | 13.x | Ubuntu 24.04 apt |
| MPICH | 4.2.x | apt (matches Met Office stack choice) |
| HDF5 (parallel) | 1.10.x | apt, `libhdf5-mpich-dev` |
| NetCDF-C / NetCDF-Fortran | 4.9.2 / 4.6.1 | built from source into `/opt/netcdf` against parallel HDF5 — versions match LFRic `software_dependencies.rst`; Ubuntu ships no parallel NetCDF package |
| PSyclone | 3.3.1 (pinned) | pip |
| rose_picker | HEAD | github.com/MetOffice/rose_picker |
| YAXT | 0.11.0, `--with-idxtype=long` (LFRic halo indices are int64) | gitlab.dkrz.de/dkrz-sw/yaxt |
| pFUnit (+gFTL, fArgParse) | 4.12.0 | Goddard-Fortran-Ecosystem |
| XIOS2 | **r2904** (donor: `vpcm_dev` image, copy-only stage) | LFRic pins r2701. The IPSL forge (`forge.ipsl.fr`) is intermittently unreachable, so the source comes from the donor image. `--build-arg XIOS_SRC=git` selects `hiker/xios-2252` instead |

NetCDF is **parallel**, so XIOS runs in `one_file` mode — which LFRic's UGRID
output requires. XIOS is configured with `--netcdf_lib netcdf4_par`. Serial
NetCDF will not work.

The `vpcm_dev` image must be present locally (`docker pull maureenjcohen/vpcm_dev`)
— it donates the XIOS source tree in a copy-only stage; none of its x86 code runs.

## Build

```bash
cd venus/container
docker build --platform linux/amd64 -t lfric_dev:amd64 .
```

**Always build x86-64**, on both laptop and cluster: the laptop runs it under QEMU
emulation, the cluster runs it natively under podman. An aarch64 image builds but
cannot run the model, so do not drop the `--platform` flag.

### After changing the stack

The code is bind-mounted, so `applications/<app>/working/` and `bin/` survive an
image rebuild. Stale objects link cleanly against a new stack and then fail
at runtime, so clear them after any change to it:

```bash
cd /lfric/apps/applications/gungho_model && rm -rf working bin
```

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
