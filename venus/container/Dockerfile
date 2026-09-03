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

# XIOS source donor: the vpcm_dev image carries the IPSL XIOS tree (svn r2904)
# and the IPSL forge is unreachable from this network. Copy-only stage -- no
# x86 code is executed. Revert to a direct `svn checkout -r 2701` of
# XIOS2/trunk when the forge is reachable again (LFRic pins r2701).
FROM --platform=linux/amd64 maureenjcohen/vpcm_dev:latest AS xiossrc

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Compilers, MPI (MPICH, matching the Met Office stack), parallel HDF5.
# NetCDF-C 4.9.2 and NetCDF-Fortran 4.6.1 are built from source below
# against parallel HDF5 (Ubuntu has no parallel NetCDF package).
RUN apt-get update && apt-get install -y --no-install-recommends \
    gfortran g++ gcc make cmake m4 \
    git subversion wget curl ca-certificates rsync \
    autoconf automake libtool pkg-config \
    mpich libmpich-dev \
    liburi-perl time \
    libhdf5-mpich-dev \
    liblapack-dev libblas-dev \
    python3 python3-pip python3-venv \
    vim less \
    && rm -rf /var/lib/apt/lists/*

# lfric_apps' dependencies.yaml pins its MetOffice repos with git@github.com:
# SSH URLs. The container has no SSH keys, and all those repos are public, so
# rewrite SSH->HTTPS here rather than editing dependencies.yaml (which must stay
# byte-identical to upstream to keep fork rebases cheap).
RUN git config --system url."https://github.com/".insteadOf "git@github.com:"

# ---------------------------------------------------------------------------
# NetCDF-C 4.9.2 with parallel HDF5 (Ubuntu has no parallel NetCDF package).
# ---------------------------------------------------------------------------
RUN wget -q https://downloads.unidata.ucar.edu/netcdf-c/4.9.2/netcdf-c-4.9.2.tar.gz \
         -O /tmp/netcdf-c.tar.gz \
    && cd /tmp && tar xf netcdf-c.tar.gz && cd netcdf-c-4.9.2 \
    && CC=mpicc \
       CPPFLAGS="-I/usr/include/hdf5/mpich" \
       LDFLAGS="-L/usr/lib/x86_64-linux-gnu/hdf5/mpich" \
       ./configure --prefix=/opt/netcdf --enable-parallel4 --disable-dap --disable-libxml2 \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/netcdf-c*

# ---------------------------------------------------------------------------
# NetCDF-Fortran 4.6.1 against the parallel NetCDF-C above.
# ---------------------------------------------------------------------------
RUN cd /tmp \
    && wget -q https://downloads.unidata.ucar.edu/netcdf-fortran/4.6.1/netcdf-fortran-4.6.1.tar.gz \
         -O netcdf-f.tar.gz \
    && tar xf netcdf-f.tar.gz && cd netcdf-fortran-4.6.1 \
    && CC=mpicc FC=mpif90 F77=mpif90 \
       CPPFLAGS="-I/opt/netcdf/include" \
       LDFLAGS="-L/opt/netcdf/lib -L/usr/lib/x86_64-linux-gnu/hdf5/mpich" \
       LD_LIBRARY_PATH=/opt/netcdf/lib:/usr/lib/x86_64-linux-gnu/hdf5/mpich \
       ./configure --prefix=/opt/netcdf \
    && make -j"$(nproc)" && make install \
    && rm -rf /tmp/netcdf-f*

ENV PATH=/opt/netcdf/bin:$PATH
ENV LD_LIBRARY_PATH=/opt/netcdf/lib:/usr/lib/x86_64-linux-gnu/hdf5/mpich

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
RUN git clone --depth 1 https://github.com/MetOffice/rose_picker.git /opt/rose_picker \
    && /opt/lfric-python/bin/pip install --no-cache-dir /opt/rose_picker

# ---------------------------------------------------------------------------
# YAXT 0.11.0 (halo exchange; DKRZ).
# ---------------------------------------------------------------------------
RUN git clone --depth 1 --branch release-0.11.0 \
        https://gitlab.dkrz.de/dkrz-sw/yaxt.git /tmp/yaxt \
    && cd /tmp/yaxt \
    && autoreconf -i \
    && CC=mpicc FC=mpif90 ./configure --prefix=/opt/yaxt \
         --with-idxtype=long --without-regard-for-quality \
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
# XIOS (IO server). LFRic pins XIOS2 r2701; this build uses r2904 from the
# vpcm_dev donor stage because the IPSL forge is currently unreachable.
# Arch files follow the pattern proven in the vpcm_dev image.
# Parallel NetCDF: enables XIOS "one_file" mode for UGRID output.
# ---------------------------------------------------------------------------
# XIOS source selection. XIOS_SRC=git uses hiker/xios-2252 -- a git mirror of
# XIOS2 trunk at r2252 maintained by an LFRic build-system author and described
# as "used for LFRic and NEMO". XIOS_SRC=donor takes r2904 from the vpcm_dev
# image. donor/r2904 is the default, being nearer LFRic's pinned r2701; switch
# to git/r2252 only to test that variable. Neither revision can run LFRic on
# aarch64 -- see BUG-001 in the bug log (path in the top-level CLAUDE.md).
ARG XIOS_SRC=donor
COPY --from=xiossrc /trunk/XIOS /opt/xios-donor
RUN if [ "$XIOS_SRC" = "git" ]; then \
        git clone --depth 1 https://github.com/hiker/xios-2252.git /opt/xios-src; \
    else \
        cp -r /opt/xios-donor /opt/xios-src; \
    fi \
    && rm -rf /opt/xios-donor \
    && rm -rf /opt/xios-src/obj /opt/xios-src/lib /opt/xios-src/bin \
              /opt/xios-src/ppsrc /opt/xios-src/done /opt/xios-src/flags \
              /opt/xios-src/cache /opt/xios-src/inc /opt/xios-src/.svn \
              /opt/xios-src/.git
WORKDIR /opt/xios-src/arch
RUN printf '%s\n' \
      'export NETCDFC=/opt/netcdf' \
      'export NETCDFF=/opt/netcdf' > arch-local.env \
 && cat <<'FCM' > arch-local.fcm
%CCOMPILER      mpicc
%FCOMPILER      mpif90
%LINKER         mpif90

# -include array/cstdint: older XIOS revisions relied on transitive libstdc++
# includes that GCC 13 no longer provides.
%BASE_CFLAGS    -w -std=c++11 -D__XIOS_EXCEPTION -include array -include cstdint
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
NETCDF_INCDIR="-I/opt/netcdf/include"
NETCDF_LIBDIR="-L/opt/netcdf/lib"
NETCDF_LIB="-lnetcdf -lnetcdff"
HDF5_INCDIR="-I/usr/include/hdf5/mpich"
HDF5_LIBDIR="-L/usr/lib/x86_64-linux-gnu/hdf5/mpich"
HDF5_LIB="-lhdf5_hl -lhdf5 -lz -lcurl"
PTH
WORKDIR /opt/xios-src
# --dev (-g -O2): XIOS is fragile under -O3 with newer GCC, and symbols keep
# crashes diagnosable. Revisit --prod once the stack is proven on this arch.
RUN ./make_xios --dev --arch local --netcdf_lib netcdf4_par --job "$(nproc)" \
    && mkdir -p /opt/xios/lib /opt/xios/inc /opt/xios/bin \
    && cp -r lib/* /opt/xios/lib/ && cp -r inc/* /opt/xios/inc/ \
    && cp bin/xios_server.exe /opt/xios/bin/

# ---------------------------------------------------------------------------
# Environment for the LFRic make-based build: compiler selection plus the
# include/link paths for netcdf, yaxt, xios, pfunit (compile.mk consumes
# FC/FPP/LDMPI/FFLAGS/LDFLAGS from the environment).
# ---------------------------------------------------------------------------
RUN NFINC=$(nf-config --includedir) && PFU=$(ls -d /opt/pfunit/PFUNIT-*) \
    && GFTLS=$(ls -d /opt/pfunit/GFTL_SHARED-* 2>/dev/null || true) \
    && FARG=$(ls -d /opt/pfunit/FARGPARSE-* 2>/dev/null || true) \
    && cat > /etc/profile.d/lfric.sh <<PROF
export FC=mpif90
export FPP="cpp -traditional-cpp"
export LDMPI=mpif90
export PFUNIT=$PFU
export FFLAGS="-I$NFINC -I/opt/yaxt/include -I/opt/xios/inc -I$PFU/include -I$GFTLS/include -I$FARG/include"
export LDFLAGS="-L/opt/netcdf/lib -L/usr/lib/x86_64-linux-gnu/hdf5/mpich -L/opt/yaxt/lib -L/opt/xios/lib -L$PFU/lib -L$GFTLS/lib -L$FARG/lib"
export LD_LIBRARY_PATH=/opt/netcdf/lib:/usr/lib/x86_64-linux-gnu/hdf5/mpich:/opt/yaxt/lib:\$LD_LIBRARY_PATH
export PATH=/opt/lfric-python/bin:/opt/netcdf/bin:\$PATH
PROF

WORKDIR /lfric
CMD ["/bin/bash", "-l"]
