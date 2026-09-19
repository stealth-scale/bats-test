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

@test "image: bash -> the pinned version" {
    run bash -c 'echo "$BASH_VERSION"'
    [[ "$output" == "${BATS_TEST_IMAGE_BASH}"* ]]
}

@test "image: bats -> the pinned version" {
    run bats --version
    [ "$output" = "Bats ${BATS_TEST_IMAGE_BATS}" ]
}

@test "image: kcov -> present, built with the nounset-safe helper" {
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

@test "image: alpine -> no /bin/bash, so scripts must use #!/usr/bin/env bash" {
    [[ "$BATS_TEST_IMAGE_DISTRO" == alpine ]] || skip "Fedora ships /bin/bash"
    [ ! -e /bin/bash ]
}

# ==============================================================================
# GROUP 02: entrypoint
# ==============================================================================

@test "entrypoint: test -> runs bats on the arguments" {
    run entrypoint test "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1..3"* ]]
}

@test "entrypoint: test on a failing suite -> non-zero" {
    run entrypoint test "$fixture/tests/failing.bats"
    [ "$status" -eq 1 ]
}

@test "entrypoint: versions -> three lines" {
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
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "coverage: "*"% of $fixture/src (floor 0%); report in $out/index.html" ]]
    [ -f "$out/index.html" ]
}

@test "kcov-bats: uncalled function -> counted as uncovered, under 100" {
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [[ "${lines[-1]}" =~ coverage:\ ([0-9]+)% ]]
    (( BASH_REMATCH[1] < 100 ))
    (( BASH_REMATCH[1] >= 60 ))
}

@test "kcov-bats: table -> a header, one row per file and a total, uncovered as ranges" {
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/greet.bats"
    [[ "$output" == *"file "*"lines  covered  percent  uncovered"* ]]
    [[ "$output" =~ tests/fixture/src/greet\.bash\ +[0-9]+\ +[0-9]+\ +[0-9]+%\ +[0-9]+(-[0-9]+)? ]]
    [[ "$output" =~ total\ +[0-9]+\ +[0-9]+\ +[0-9]+% ]]
}

@test "kcov-bats: --lines -> the source of every uncovered line" {
    run kcov-bats --src "$fixture/src" --out "$out" --lines -- "$fixture/tests/greet.bats"
    [[ "$output" == *"greet.bash:"*": printf 'this line is not covered"* ]]
}

@test "kcov-bats: --min above the result -> exit 1 after the coverage line" {
    run kcov-bats --src "$fixture/src" --out "$out" --min 100 -- "$fixture/tests/greet.bats"
    [ "$status" -eq 1 ]
    [[ "${lines[-1]}" == *"(floor 100%)"* ]]
}

@test "kcov-bats: failing suite -> bats' status, not kcov's" {
    run kcov-bats --src "$fixture/src" --out "$out" -- "$fixture/tests/failing.bats"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not ok 1 fails on purpose"* ]]
}

@test "kcov-bats: child bash under set -u -> traced without an unbound variable error" {
    run kcov-bats --src "$fixture/src" --out "$out" -- --filter 'set -u' "$fixture/tests/greet.bats"
    [ "$status" -eq 0 ]
    [[ "$output" != *"unbound variable"* ]]
}

@test "kcov-bats: --min out of range -> usage error, exit 2" {
    run kcov-bats --min 200 -- "$fixture/tests/greet.bats"
    [ "$status" -eq 2 ]
}

@test "kcov-bats: missing source directory -> exit 2" {
    run kcov-bats --src /nonexistent -- "$fixture/tests/greet.bats"
    [ "$status" -eq 2 ]
}

@test "kcov-bats: --help -> prints the usage" {
    run kcov-bats --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--min PERCENT"* ]]
}
