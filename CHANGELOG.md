# Changelog

Every change a consumer would notice is recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The Alpine image: bash at a chosen version, bats-core at a chosen version, GNU tools, jq,
  git and kcov, published for bash 4.4, 5.1, 5.2 and 5.3 by bats-core 1.7.0 and 1.14.0.
- The Fedora image with Fedora's bash and bats, for glibc.
- `entrypoint` with `test`, `coverage`, `shell` and `versions`.
- `kcov-bats`: bats under kcov with bats' own exit status, a table per file with the
  uncovered lines, the percentage from cobertura and a `--min` floor.
- kcov v43 built with a fix to its bash helper, so a traced `bash -c` child under `set -u`
  no longer fails with `BASH_SOURCE: unbound variable`.
- Tests of the image, run inside it: tools, versions, every entrypoint command, and the
  exit status and floor semantics of `kcov-bats`.

[Unreleased]: https://github.com/stealth-scale/bats-test/commits/main
