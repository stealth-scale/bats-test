# The builder variant of the stealth test image: bats plus the tools a build needs and
# a container engine to run one in.
#
# The other two images exist to run bats. This one exists to run a suite that builds
# software: it compiles a package, puts it in an OCI store and asks whether two builds
# of one source gave the same bytes. That suite needs a compiler, rpmbuild, the image
# tools, and a container engine, because the thing under test runs every build step in
# a container of its own.
#
# The base is podman's own image rather than a Fedora with podman added. Running podman
# inside a container rootless needs newuidmap and newgidmap with their capabilities, an
# /etc/subuid and /etc/subgid for the running user, fuse-overlayfs and a storage
# configuration that does not assume a host. That is a set of decisions somebody
# maintains upstream, and a second copy of it here would be a worse one.
#
# A consumer mounts its checkout at /code and runs `test` or `shell`; see bin/entrypoint.
# It has to be run with --device /dev/fuse and without --network=none, which is what the
# Makefile's BUILDER_RUN does. There is no coverage command here: kcov is not installed,
# because a suite that shells out to a container engine is not one kcov can read.
FROM quay.io/podman/stable

ARG BATS_VERSION=1.14.0

# make, gcc and rpm-build are what a package build calls for. skopeo moves images between
# an OCI layout and a container store. jq reads what the library writes. The language
# packs are here because a reproducibility suite sets a locale on purpose and a locale
# that is not installed is not a locale a build was run under.
RUN dnf install -y --setopt=install_weak_deps=False \
        make gcc gcc-c++ rpm-build rpm-sign skopeo jq diffutils findutils gawk \
        patch xz bzip2 zstd which parallel \
        glibc-langpack-en glibc-langpack-nl \
    && dnf clean all

RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
        https://github.com/bats-core/bats-core.git /tmp/bats \
    && /tmp/bats/install.sh /usr/local \
    && rm -rf /tmp/bats

# crane is a Go binary and not a package anywhere, which is the same reason the library
# treats it as a build-host tool rather than a dependency of the product.
ARG CRANE_VERSION=0.21.3
RUN set -eu; \
    case "$(uname -m)" in \
        x86_64) arch=x86_64 ;; \
        aarch64) arch=arm64 ;; \
        *) echo "no crane for $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/crane.tgz \
        "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_${arch}.tar.gz"; \
    tar -xzf /tmp/crane.tgz -C /usr/local/bin crane; \
    rm -f /tmp/crane.tgz

COPY bin/entrypoint /usr/local/bin/

# The image tests read these.
RUN printf 'BATS_TEST_IMAGE_BASH=%s\nBATS_TEST_IMAGE_BATS=%s\n' \
        "$(bash -c 'echo ${BASH_VERSION%%(*}')" "$(bats --version | sed 's/^Bats //')" \
        > /etc/bats-test-image \
    && cat /etc/bats-test-image
ENV BATS_TEST_IMAGE_DISTRO=builder

# The user podman's own image sets up for rootless nesting, with its subuid range.
USER podman
WORKDIR /code
ENTRYPOINT ["entrypoint"]
CMD ["test"]
