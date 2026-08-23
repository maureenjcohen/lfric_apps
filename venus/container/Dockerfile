##############################################################################
# lfric_dev: development image for LFRic-Venus (WP6).
#
# Provides the full LFRic build stack; the lfric_core and lfric_apps clones
# are bind-mounted at run time, mirroring the vpcm_dev workflow:
#
#   docker run -it --rm \
#     -v ~/repos/lfric_core:/lfric/core \
#     -v ~/repos/lfric_apps:/lfric/apps \
#     lfric_dev:latest
#
# The recipe is arch-agnostic: build natively on aarch64 for fast local
# iteration, and for x86-64 (cluster/podman) with `docker buildx --platform`.
##############################################################################

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Compilers, MPI (MPICH, matching the Met Office stack), NetCDF stack from
# apt: Ubuntu 24.04 carries NetCDF-C 4.9.2 / NetCDF-Fortran 4.6.1 -- the
# exact versions listed in LFRic's software_dependencies.rst.
RUN apt-get update && apt-get install -y --no-install-recommends \
    gfortran g++ gcc make cmake m4 \
    git subversion wget curl ca-certificates rsync \
    autoconf automake libtool pkg-config \
    mpich libmpich-dev \
    libhdf5-dev libnetcdf-dev libnetcdff-dev \
    liblapack-dev libblas-dev \
    python3 python3-pip python3-venv \
    vim less \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Python tools: PSyclone (version pinned per LFRic docs) + build helpers.
# ---------------------------------------------------------------------------
RUN python3 -m venv /opt/lfric-python \
    && /opt/lfric-python/bin/pip install --no-cache-dir \
       psyclone==3.3.1 jinja2 pyyaml
ENV PATH=/opt/lfric-python/bin:$PATH

# ---------------------------------------------------------------------------
# rose_picker (GPL-utils, public GitHub mirror).
# ---------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/MetOffice/rose_picker.git /opt/rose_picker
ENV PATH=/opt/rose_picker/bin:$PATH \
    PYTHONPATH=/opt/rose_picker/lib/python:$PYTHONPATH

# ---------------------------------------------------------------------------
# YAXT 0.11.0 (halo exchange; DKRZ).
# ---------------------------------------------------------------------------
RUN git clone --depth 1 --branch release-0.11.0 \
        https://gitlab.dkrz.de/dkrz-sw/yaxt.git /tmp/yaxt \
    && cd /tmp/yaxt \
    && autoreconf -i \
    && CC=mpicc FC=mpif90 ./configure --prefix=/opt/yaxt \
         --without-regard-for-quality \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/yaxt

# ---------------------------------------------------------------------------
# pFUnit 4.12.0 (unit-test framework; brings gFTL, gFTL-shared, fArgParse).
# ---------------------------------------------------------------------------
RUN git clone --recursive --depth 1 --branch v4.12.0 \
        https://github.com/Goddard-Fortran-Ecosystem/pFUnit.git /tmp/pfunit \
    && cd /tmp/pfunit \
    && cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/pfunit \
         -DCMAKE_Fortran_COMPILER=mpif90 -DMPI=YES \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build \
    && rm -rf /tmp/pfunit

# ---------------------------------------------------------------------------
# XIOS2 r2701 (IO server; revision per LFRic software_dependencies.rst).
# Arch files follow the pattern proven in the vpcm_dev image.
# NOTE: if the XIOS2 path 404s, fall back to .../svn/XIOS/trunk (the URL the
# vpcm_dev image used). Serial NetCDF: use XIOS "multiple_file" mode.
# ---------------------------------------------------------------------------
RUN svn checkout -r 2701 \
      --trust-server-cert-failures="other,unknown-ca,cn-mismatch,expired,not-yet-valid" \
      https://forge.ipsl.jussieu.fr/ioserver/svn/XIOS2/trunk /opt/xios-src
WORKDIR /opt/xios-src/arch
RUN printf '%s\n' \
      'export NETCDFC=/usr' \
      'export NETCDFF=/usr' > arch-local.env \
 && cat <<'FCM' > arch-local.fcm
%CCOMPILER      mpicc
%FCOMPILER      mpif90
%LINKER         mpif90

%BASE_CFLAGS    -w -std=c++11 -D__XIOS_EXCEPTION
%PROD_CFLAGS    -O3 -D BOOST_DISABLE_ASSERTS
%DEV_CFLAGS     -g -O2
%DEBUG_CFLAGS   -g -DBZ_DEBUG

%BASE_FFLAGS    -D__NONE__ -ffree-line-length-none -fallow-argument-mismatch
%PROD_FFLAGS    -O3
%DEV_FFLAGS     -g -O2
%DEBUG_FFLAGS   -g

%BASE_INC       -D__NONE__
%BASE_LD        -lstdc++

%CPP            mpicc -EP
%FPP            cpp -P
%MAKE           make
FCM
RUN cat <<'PTH' > arch-local.path
NETCDF_INCDIR="-I/usr/include"
NETCDF_LIBDIR=""
NETCDF_LIB="-lnetcdf -lnetcdff"
HDF5_INCDIR="-I/usr/include/hdf5/serial"
HDF5_LIBDIR="-L/usr/lib"
HDF5_LIB="-lhdf5_serial_hl -lhdf5_serial -lz -lcurl"
PTH
WORKDIR /opt/xios-src
RUN ./make_xios --prod --arch local --job "$(nproc)" \
    && mkdir -p /opt/xios/lib /opt/xios/inc \
    && cp -r lib/* /opt/xios/lib/ && cp -r inc/* /opt/xios/inc/

# ---------------------------------------------------------------------------
# Environment for the LFRic make-based build: compiler selection plus the
# include/link paths for netcdf, yaxt, xios, pfunit (compile.mk consumes
# FC/FPP/LDMPI/FFLAGS/LDFLAGS from the environment).
# ---------------------------------------------------------------------------
RUN NFINC=$(nf-config --includedir) && cat > /etc/profile.d/lfric.sh <<PROF
export FC=mpif90
export FPP="cpp -traditional-cpp"
export LDMPI=mpif90
export FFLAGS="-I$NFINC -I/opt/yaxt/include -I/opt/xios/inc -I/opt/pfunit/include"
export LDFLAGS="-L/opt/yaxt/lib -L/opt/xios/lib -L/opt/pfunit/lib"
export LD_LIBRARY_PATH=/opt/yaxt/lib:\$LD_LIBRARY_PATH
export PATH=/opt/lfric-python/bin:/opt/rose_picker/bin:\$PATH
export PYTHONPATH=/opt/rose_picker/lib/python:\$PYTHONPATH
PROF

WORKDIR /lfric
CMD ["/bin/bash", "-l"]
