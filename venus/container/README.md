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

### Running the model

```bash
export OMP_NUM_THREADS=1
export HDF5_USE_FILE_LOCKING=FALSE
ulimit -s unlimited
mpiexec -n 1 ../bin/gungho_model configuration.nml : -n 1 /opt/xios/bin/xios_server.exe
```

`OMP_NUM_THREADS` is required. The binary carries `-fopenmp`, so left unset OpenMP sizes
its thread team to the core count and every MPI rank oversubscribes the node. Rose sets
it; a hand-rolled `mpiexec` does not.

`HDF5_USE_FILE_LOCKING=FALSE` is required when the run directory sits on a network
filesystem that does not provide the POSIX locking HDF5 expects — CephFS among them.
While locking is enabled, parallel NetCDF file creation fails with `Permission denied`
as soon as more than one process writes.

The stack limit matters: LFRic and XIOS both use large automatic arrays.

### Optimised builds

The default profile is `fast-debug`, which on gfortran maps `SAFE_OPTIMISATION` to `-Og`
— optimise-for-debugging, not optimise. Other compilers map it to `-O2`. For a fast
binary without `-Ofast`'s `-ffast-math`:

```bash
cd /lfric/apps/applications/gungho_model
rm -rf working bin
make -j8 build PROFILE=fast-debug FFLAGS_SAFE_OPTIMISATION=-O2 \
     CORE_ROOT_DIR=/lfric/core APPS_ROOT_DIR=/lfric/apps
```

Clearing `working` and `bin` is required: the build system does not track flag changes,
so objects built at the old level would link straight in.
