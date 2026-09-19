# Changelog

Every change a consumer would notice is recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-19

First tagged release.

### Added

- The Alpine image: bash at a chosen version, bats-core at a chosen version, GNU tools, jq,
  git and kcov, published for bash 4.4, 5.1, 5.2 and 5.3 by bats-core 1.7.0 and 1.14.0.
- The Fedora image with Fedora's bash and bats, for glibc.
- `entrypoint` with `test`, `coverage`, `shell` and `versions`. It is the init of the
  container: SIGINT and SIGTERM reach every process of a run, kcov included, and a
  second signal kills the run.
- `kcov-bats`: bats under kcov with bats' own exit status, a table per file with the
  uncovered lines, truncated percentages from the line counts of the report, a `--min`
  floor, and kcov's own output in `OUT/kcov.log` instead of the terminal.
- kcov v43 built with three fixes to its bash engine: a traced `bash -c` child under
  `set -u` no longer fails with `BASH_SOURCE: unbound variable`, a quote inside a `[[ ]]`
  value or in bash 5.3's `$'…'` quoting no longer hides every hit after it, and a
  command that spans lines counts as one line, so a multi-line string, awk program or
  `[[ ]]` test, `fi ;;` and `done < <(cmd)` no longer show as uncovered.
- Tests of the image, run inside it: tools, versions, every entrypoint command, its
  signal handling, and the exit status, floor and output semantics of `kcov-bats`.

[Unreleased]: https://github.com/stealth-scale/bats-test/compare/v1.0.0...main
[1.0.0]: https://github.com/stealth-scale/bats-test/releases/tag/v1.0.0
