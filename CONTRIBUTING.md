# Contributing

## Getting set up

You need GNU make, [ShellCheck](https://www.shellcheck.net) and Podman or Docker. The
first `make image` builds kcov from source, which takes a few minutes. Later builds reuse
that layer.

```sh
git clone git@github.com:stealth-scale/bats-test.git
cd bats-test
make check
```

## Before you open a pull request

```sh
make lint     # shellcheck over bin/ and the tests
make test     # tests/image.bats inside the default image
make matrix   # every cell, when a change touches the Containerfiles or bin/
make check    # what CI runs per cell: lint, then test
```

`RUNTIME=docker` selects Docker. The default is Podman.

## A change to the image

- A tool goes into `Containerfile` and `Containerfile.fedora`, or the README says which tag
  lacks it. `Containerfile.builder` carries what a build calls for, and its README section
  lists it.
- A command of the entrypoint gets a test in `tests/image.bats`, named
  `<command>: <case> -> <expectation>`, and a row in the README table.
- A new bash or bats version is one more value in `BASH_VERSIONS` or `BATS_VERSIONS` in the
  Makefile and in the matrix of `.github/workflows/ci.yml`.
- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for a change a
  consumer would notice.

## Releasing

Images are published from `main` on every push, under their version tags. A release is a
tag on `main` for the changelog:

1. Move the `Unreleased` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD`
   heading and add the compare link at the foot of the file.
2. Commit as `chore: release vX.Y.Z`.
3. `git tag -s vX.Y.Z -m vX.Y.Z && git push --follow-tags`.

## Conventions

Commit messages take the form `type(scope): summary`, as the standards for every stealth
repository set out at https://docs.stealthscale.io. The scope is `alpine`, `fedora`,
`builder`, `entrypoint` or `kcov-bats` when a change stays in one.

## Review

A pull request is reviewed by a maintainer of the stealth-scale organisation.
