#!/usr/bin/env bats

# ==============================================================================
# bats-test image - Test Suite
# ==============================================================================
# Runs inside the image, with this repository mounted at /code:
#   podman run --rm -v "$PWD:/code:ro" -v "$PWD/coverage:/code/coverage" IMAGE test tests/image.bats
#
#   01. Tools and versions
#   02. entrypoint
#   03. kcov-bats
# ==============================================================================

setup() {
    set -Euo pipefail
    bats_require_minimum_version 1.5.0
    fixture=/code/tests/fixture
    out="/code/coverage/$BATS_TEST_NUMBER"
    # The Alpine image pins the versions as build arguments; Fedora records dnf's.
    # shellcheck source=/dev/null
    [[ -f /etc/bats-test-image ]] && source /etc/bats-test-image
    : "${BATS_TEST_IMAGE_BASH:?}" "${BATS_TEST_IMAGE_BATS:?}" "${BATS_TEST_IMAGE_DISTRO:?}"
}

# start_entrypoint ARGUMENTS...
#   Starts the entrypoint in the background, as the runtime starts PID 1: with
#   SIGINT at its default. A plain `&` hands a child SIGINT ignored, which bash
#   cannot trap afterwards. Sets `pid`.
start_entrypoint() {
    set -m
    entrypoint "$@" </dev/null &
    pid=$!
    set +m
}

# ==============================================================================
# GROUP 01: Tools and versions
# ==============================================================================

# Skips a test that needs kcov, which the builder variant does not carry.
require_kcov() {
    command -v kcov > /dev/null 2>&1 || skip 'this image has no kcov'
}

@test "image: bash -> the pinned version" {
    run bash -c 'echo "$BASH_VERSION"'
    [[ "$output" == "${BATS_TEST_IMAGE_BASH}"* ]]
}

@test "image: bats -> the pinned version" {
    run bats --version
    [ "$output" = "Bats ${BATS_TEST_IMAGE_BATS}" ]
}

@test "image: kcov -> present, built with the nounset-safe helper" {
    require_kcov
    run kcov --version
    [[ "$output" == kcov* ]]
    run strings /usr/local/bin/kcov
    # shellcheck disable=SC2016  # the literal text of kcov's helper is the point
    [[ "$output" == *'kcov@${BASH_SOURCE-}@'* ]]
    # shellcheck disable=SC2016
    [[ "$output" != *'kcov@${BASH_SOURCE}@'* ]]
}

@test "image: GNU tools -> coreutils, sed, grep, awk, find, diff, jq, git" {
    [[ "$(sed --version | head -1)" == *GNU* ]]
    [[ "$(grep --version | head -1)" == *GNU* ]]
    [[ "$(awk --version | head -1)" == *GNU* ]]
    # shellcheck disable=SC2185  # --version takes no path
    [[ "$(find --version 2>&1 | head -1)" == *GNU* ]]
    [[ "$(diff --version | head -1)" == *GNU* ]]
    [[ "$(date --version | head -1)" == *GNU* ]]
    command -v jq
    command -v git
}

@test "image: flock waits for a lock" {
    # busybox supplies a flock with only -s, -x, -u and -n. Code that asks
    # for a bounded wait gets "unrecognized option" and reads the failure as
    # somebody else holding the lock, so a test of it passes for the wrong
    # reason. The flock package supplies the one that takes -w.
    run flock -w 1 /tmp/image-flock.lock true
    [ "$status" -eq 0 ]

    run flock --help
    [[ "$output" != *"BusyBox"* ]]
}

@test "image: bats can run a suite in parallel" {
    # bats --jobs needs GNU parallel and says so rather than falling back to
    # running one test at a time. Every test is its own process, so a suite
    # that sources a large library pays for reading it once per test, and a
    # machine with cores to spare should be able to use them.
    run parallel --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"GNU parallel"* ]]
}

@test "image: bats --jobs -> runs every test and reports them all" {
    # The count is what matters. A parallel run that loses a test, or one
    # that reports a test twice, is worse than a slow one.
    local suite="${BATS_TEST_TMPDIR}/parallel.bats"
    {
        printf '#!/usr/bin/env bats\n'
        local i
        for i in 1 2 3 4 5 6 7 8; do
            printf '@test "case %s" { true; }\n' "$i"
        done
    } > "${suite}"

    run bats --jobs 4 "${suite}"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^ok ' <<< "$output")" -eq 8 ]
}

@test "image: builder -> carries the tools a build calls for" {
    # The other two images exist to run bats. This one exists to run a suite
    # that builds software, which needs a compiler, rpmbuild and the image
    # tools rather than just a shell.
    [[ "$BATS_TEST_IMAGE_DISTRO" == builder ]] || skip 'not the builder image'

    local tool
    for tool in make gcc rpmbuild skopeo crane jq patch; do
        run command -v "$tool"
        [ "$status" -eq 0 ]
    done
}

@test "image: builder -> carries a container engine" {
    # A build runs every step in a container of its own, so the image that
    # runs the suite has to be able to start one.
    [[ "$BATS_TEST_IMAGE_DISTRO" == builder ]] || skip 'not the builder image'

    run command -v podman
    [ "$status" -eq 0 ]
}

@test "image: builder -> can start a container from inside this one" {
    # Rootless nesting, which the RFC lists as a risk needing a test. It
    # wants /dev/fuse and the calling user mapped onto this image's own,
    # which is what the Makefile's BUILDER_RUN passes.
    [[ "$BATS_TEST_IMAGE_DISTRO" == builder ]] || skip 'not the builder image'
    [ -e /dev/fuse ] || skip 'no /dev/fuse, so no nesting'

    run podman run --rm docker.io/library/alpine:3.22 true
    [ "$status" -eq 0 ]
}

@test "image: builder -> a nested container inherits this one's hostname" {
    # It cannot set its own: it shares this UTS namespace, and asking for a
    # private one is refused by the kernel. What it inherits is what was
    # pinned outside, which is how a build still cannot see the machine.
    [[ "$BATS_TEST_IMAGE_DISTRO" == builder ]] || skip 'not the builder image'
    [ -e /dev/fuse ] || skip 'no /dev/fuse, so no nesting'

    local mine
    mine=$(cat /etc/hostname)

    run podman run --rm --network none docker.io/library/alpine:3.22 hostname
    [ "$status" -eq 0 ]
    [ "$output" = "$mine" ]
}

@test "image: builder -> a nested container is refused its own hostname" {
    # Recorded because it is the reason the hostname is a setting rather
    # than a constant: a library that always passes --hostname cannot run
    # nested at all.
    [[ "$BATS_TEST_IMAGE_DISTRO" == builder ]] || skip 'not the builder image'
    [ -e /dev/fuse ] || skip 'no /dev/fuse, so no nesting'

    run podman run --rm --hostname something docker.io/library/alpine:3.22 true
    [ "$status" -ne 0 ]
    [[ "$output" == *'UTS namespace'* ]]
}

@test "image: alpine -> /bin/bash is the bash this image was built with" {
    # rpm pulls in Alpine's own bash, so /bin/bash exists whether we want it
    # or not. It is a symlink to the built one, so a script with #!/bin/bash
    # and a script with #!/usr/bin/env bash run the same interpreter.
    [[ "$BATS_TEST_IMAGE_DISTRO" == alpine ]] || skip "Fedora ships its own /bin/bash"

    [ -L /bin/bash ]
    [ "$(readlink /bin/bash)" = /usr/local/bin/bash ]

    run /bin/bash --version
    [[ "$output" == *"version ${BATS_TEST_IMAGE_BASH}"* ]]
}

# ==============================================================================
# GROUP 02: entrypoint
# ==============================================================================

@test "entrypoint: test -> runs bats on the arguments" {
    run entrypoint test "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1..5"* ]]
}

@test "entrypoint: test on a failing suite -> non-zero" {
    run entrypoint test "$fixture/tests/failing.bats"
    [ "$status" -eq 1 ]
}

@test "entrypoint: versions -> three lines" {
    # Three whatever the variant, because a variant without kcov still has a
    # bash and a bats worth naming.
    run entrypoint versions
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[0]}" == "bash ${BATS_TEST_IMAGE_BASH}"* ]]
    [ "${lines[1]}" = "bats ${BATS_TEST_IMAGE_BATS}" ]
}

@test "entrypoint: other command -> executed as is" {
    run entrypoint jq --version
    [ "$status" -eq 0 ]
    [[ "$output" == jq-* ]]
}

@test "entrypoint: other command -> exits with its status" {
    run entrypoint bash -c 'exit 7'
    [ "$status" -eq 7 ]
}

@test "entrypoint: stdin -> reaches the command" {
    run bash -c 'printf hello | entrypoint cat'
    [ "$status" -eq 0 ]
    [ "$output" = hello ]
}

@test "entrypoint: help -> lists the commands" {
    run entrypoint --help
    [[ "$output" == *"coverage"* ]]
}

@test "entrypoint: SIGINT -> ends the command, exit 130" {
    start_entrypoint sleep 30
    sleep 0.5
    kill -s INT "$pid"
    local status=0
    wait "$pid" || status=$?
    [ "$status" -eq 130 ]
}

@test "entrypoint: SIGTERM -> ends the command's children too, exit 143" {
    local pidfile="$BATS_TEST_TMPDIR/child.pid"
    # shellcheck disable=SC2016  # the script runs in the child bash
    start_entrypoint bash -c 'sleep 30 & echo "$!" > "$1"; wait' _ "$pidfile"
    local waited=0
    until [[ -s "$pidfile" ]] || (( waited++ > 10 )); do sleep 0.2; done
    [ -s "$pidfile" ]
    kill -s TERM "$pid"
    local status=0
    wait "$pid" || status=$?
    [ "$status" -eq 143 ]
    sleep 0.2
    run ! kill -0 "$(cat "$pidfile")"
}

@test "entrypoint: repeated signal -> kills a command that ignored the first, exit 137" {
    start_entrypoint bash -c 'trap "" TERM; sleep 30 & wait'
    sleep 0.5
    kill -s TERM "$pid"
    sleep 0.5
    kill -0 "$pid"
    kill -s TERM "$pid"
    local status=0
    wait "$pid" || status=$?
    [ "$status" -eq 137 ]
}

# ==============================================================================
# GROUP 03: kcov-bats
# ==============================================================================

@test "kcov-bats: passing suite -> exit 0 and a coverage line" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "coverage: "*"% of $fixture/src (floor 0%); report in $out/index.html" ]]
    [ -f "$out/index.html" ]
}

@test "kcov-bats: uncalled function -> counted as uncovered, under 100" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [[ "${lines[-1]}" =~ coverage:\ ([0-9]+)% ]]
    (( BASH_REMATCH[1] < 100 ))
    (( BASH_REMATCH[1] >= 60 ))
}

@test "kcov-bats: table -> a header, one row per file and a total, uncovered as ranges" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [[ "$output" == *"file "*"lines  covered  percent  uncovered"* ]]
    [[ "$output" =~ tests/fixture/src/greet\.bash\ +[0-9]+\ +[0-9]+\ +[0-9]+%\ +[0-9]+(-[0-9]+)? ]]
    [[ "$output" =~ total\ +[0-9]+\ +[0-9]+\ +[0-9]+% ]]
}

@test "kcov-bats: --lines -> the source of every uncovered line" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" --lines -- "$fixture/tests/greet.bats"
    [[ "$output" == *"greet.bash:"*": printf 'this line is not covered"* ]]
}

@test "kcov-bats: --min above the result -> exit 1 after the coverage line" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" --min 100 -- "$fixture/tests/greet.bats"
    [ "$status" -eq 1 ]
    [[ "${lines[-1]}" == *"(floor 100%)"* ]]
}

@test "kcov-bats: failing suite -> bats' status, not kcov's" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/failing.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok 1 fails on purpose"* ]]
}

@test "kcov-bats: child bash under set -u -> traced without an unbound variable error" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- --filter 'set -u' "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound variable"* ]]
}

@test "kcov-bats: lines bash never reports -> not counted, a command that spans lines is one" {
    require_kcov
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/lines.bats"
    [ "$status" -eq 0 ]
    [[ "$output" =~ tests/fixture/src/lines\.bash\ +18\ +18\ +100% ]]
}

@test "kcov-bats: kcov's own output -> in OUT/kcov.log, not on stderr" {
    require_kcov
    run --separate-stderr kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [ "$stderr" = "" ]
    # The trace lines of the multi-line comparison in greet.bats, which kcov cannot place.
    [[ "$(cat "$out/kcov.log")" == "hello, b == "* ]]
}

@test "kcov-bats: bats' own stderr -> on stderr" {
    require_kcov
    run --separate-stderr kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/missing.bats"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"missing.bats"*"does not exist"* ]]
}

@test "kcov-bats: --min out of range -> usage error, exit 2" {
    require_kcov
    run kcov-bats --min 200 -- "$fixture/tests/greet.bats"
    [ "$status" -eq 2 ]
}

@test "kcov-bats: missing source directory -> exit 2" {
    require_kcov
    run kcov-bats --src /nonexistent -- "$fixture/tests/greet.bats"
    [ "$status" -eq 2 ]
}

@test "kcov-bats: --help -> prints the usage" {
    require_kcov
    run kcov-bats --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--min PERCENT"* ]]
}
