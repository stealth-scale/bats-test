# bats-test

The container image the stealth repositories run their bats suites in. One image, built
and tested here, published to `ghcr.io/stealth-scale/bats-test`, pulled by every consumer.

| Tag | Contents |
| --- | --- |
| `bash5.2-bats1.14.0`, also `latest` | Alpine, bash 5.2, bats-core 1.14.0 |
| `bash{4.4,5.1,5.2,5.3}-bats{1.7.0,1.14.0}` | the bash by bats matrix, on Alpine |
| `fedora` | Fedora 44 with its own bash and bats, glibc |

Every tag has the GNU tools in place of the busybox applets, jq, git, and kcov with one fix
of its own. The section on kcov states the fix.

## Using it

Mount the checkout at `/code` and name a command:

```sh
podman run --rm -v "$PWD:/code:ro" ghcr.io/stealth-scale/bats-test test
podman run --rm -v "$PWD:/code:ro" ghcr.io/stealth-scale/bats-test test tests/unit
podman run --rm -v "$PWD:/code:ro" -v "$PWD/coverage:/code/coverage" \
    ghcr.io/stealth-scale/bats-test coverage --min 90
```

| Command | What it does |
| --- | --- |
| `test [BATS ARGUMENTS]` | `bats`, by default `--recursive tests/` |
| `coverage [--src DIR] [--out DIR] [--min PERCENT] [--lines] [-- BATS ARGUMENTS]` | the suite under kcov, then the coverage table of `DIR`, default `/code/src`; the report goes to `/code/coverage` |
| `shell` | an interactive bash |
| `versions` | bash, bats and kcov versions |
| anything else | run as is: `jq --version`, `bash -c '…'` |

The image runs as whatever user the caller names, needs no capability and no network,
and `coverage` needs only the report directory writable. The entrypoint is the init of
the container. It runs the command in its own process group and forwards SIGINT and
SIGTERM to that group, so Ctrl+C and `podman stop` end a run and every process under
it, kcov included. A second signal kills the group. `--init` is not needed. The
Makefiles of the consumers carry the full `run` line.

`coverage` prints a table after the suite, one row per file and a total, with the
uncovered lines as ranges. `--lines` adds the source of each uncovered line.

```
file               lines  covered  percent  uncovered
src/matrix.bash      188      176      93%  135-145, 482, 484
total                188      176      93%

coverage: 93% of /code/src (floor 90%); report in /code/coverage/index.html
```

It exits with bats' own status, then fails when the total is under `--min`. The last
line is the summary, for scripts.

## Why kcov is built from source

kcov traces bash through a helper it injects into every shell, and that helper expands
`${BASH_SOURCE}` without a default. At the top level of a `bash -c` child that runs with
`set -u`, `BASH_SOURCE` is unset, so the child dies on its first command with
`BASH_SOURCE: unbound variable`. Any suite that starts such children fails only under
kcov. [patches/kcov-bash-helper-nounset.patch](patches/kcov-bash-helper-nounset.patch)
guards the expansion. The image builds kcov v43 with it, from kcov's own Alpine and Fedora
recipes. The patch is meant for upstream.

Two more things about kcov's bash engine worth knowing:

- A double-quoted string that spans lines counts each inner line as a line, and credits
  the hit to the closing line. A report with a long string body shows a few false misses.
- A string line that is a rule of `=` and ends in the closing quote stops the parser for
  the rest of the file. Put such a rule in a variable.

## Working here

```sh
make image                                   # bash 5.2, bats 1.14.0, on Alpine
make image BASH_VERSION=4.4 BATS_VERSION=1.7.0
make image DISTRO=fedora
make test                                    # the image's own tests, inside it
make matrix                                  # every published cell, built and tested
make lint                                    # shellcheck over the scripts and the tests
```

`RUNTIME=docker` selects Docker. The default is Podman. A local build gets the same name
as the published image, so a consumer picks it up without a pull.

CI builds and tests every cell on each pull request, and pushes them on `main`.

[CONTRIBUTING.md](CONTRIBUTING.md) has the rest.

## License

[MIT](LICENSE). Copyright Stealth Scale B.V. kcov is GPL-2.0. The image carries its binary
and the patch.
