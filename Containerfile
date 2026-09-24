# The stealth test image for bats: a pinned bash, a pinned bats-core, kcov, the GNU
# tools and jq, plus `kcov-bats`, which runs a suite under kcov and reports coverage.
#
#   BASH_VERSION  a tag of docker.io/library/bash: 4.4, 5.0, 5.1, 5.2, 5.3, or a release
#   BATS_VERSION  a bats-core release, 1.7.0 or later
#   KCOV_VERSION  a kcov tag
#
# A consumer mounts its checkout at /code and runs `test`, `coverage` or `shell`;
# see bin/entrypoint.
ARG BASH_VERSION=5.2

# kcov is built from source with the three patches in patches/, which fix its bash
# engine; the README states what each one changes. The recipe is kcov's own
# Dockerfile for Alpine.
FROM docker.io/library/alpine:3.22 AS kcov
ARG KCOV_VERSION=v43
RUN apk add --no-cache binutils-dev build-base cmake git curl-dev curl-static libdw openssl-dev \
        ninja-build python3 zlib-dev elfutils-dev libstdc++-dev
COPY patches /tmp/patches
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "${KCOV_VERSION}" \
        https://github.com/SimonKagstrom/kcov.git /src \
    && cd /src \
    && git apply /tmp/patches/*.patch \
    && mkdir build && cd build \
    && PATH="$PATH:/usr/lib/ninja-build/bin" cmake -G Ninja .. >/dev/null \
    && cmake --build . >/dev/null \
    && cmake --build . --target install >/dev/null

FROM docker.io/library/bash:${BASH_VERSION}
ARG BASH_VERSION
ARG BATS_VERSION=1.14.0

# The GNU tools replace the busybox applets, so a suite sees the userland its library
# targets. tar and the compressors are here for the same reason: busybox tar takes none
# of the options a reproducible archive needs. rpm brings rpmbuild and rpmkeys, so a
# suite can make a package and ask the real tool about it rather than a mock, which is
# the only way to catch an option the tool does not have. The lib* packages are what
# kcov links against.
#
# rpm depends on rpm-scripts, which depends on Alpine's own bash, so /bin/bash appears
# and would shadow the bash this image was built to test. The symlink below points it
# at the built one, so there is one bash here whichever path reaches it.
#
# parallel is what bats --jobs runs a suite through. Without it bats runs one test at a
# time, and a test costs the same again in setup as it does in assertions: a suite that
# sources a large library re-reads the whole of it per test, because every test is its
# own process. A machine with cores to spare should use them.
RUN apk add --no-cache coreutils findutils grep sed gawk diffutils git ca-certificates jq yq \
        tar gzip bzip2 xz zstd curl iproute2 rpm flock parallel \
        libcurl libdw zlib libgcc libstdc++ binutils-dev python3 \
    && git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
        https://github.com/bats-core/bats-core.git /tmp/bats \
    && /tmp/bats/install.sh /usr/local \
    && rm -rf /tmp/bats \
    && ln -sf /usr/local/bin/bash /bin/bash

COPY --from=kcov /usr/local/bin/kcov* /usr/local/bin/
COPY bin/entrypoint bin/kcov-bats bin/bats-recording-status /usr/local/bin/

ENV BATS_TEST_IMAGE_BASH="${BASH_VERSION}" \
    BATS_TEST_IMAGE_BATS="${BATS_VERSION}" \
    BATS_TEST_IMAGE_DISTRO=alpine

WORKDIR /code
ENTRYPOINT ["entrypoint"]
CMD ["test"]
