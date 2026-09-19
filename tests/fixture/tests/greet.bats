#!/usr/bin/env bats
load ../src/greet
setup() { bats_require_minimum_version 1.5.0; }
# First on purpose: bash 5.3 traces this value as $'it\'s\ttabbed', and a kcov that
# misreads the escaped quote discards every trace line after it.
@test "greet: quote and tab -> greets it, and kcov reads past the ANSI-C quoted trace" {
    local name=$'it\'s\ttabbed'
    run greet "$name"
    [ "$output" = "hello, $name" ]
}
@test "greet: name -> greets it" { run greet world; [ "$output" = "hello, world" ]; }
@test "greet: no name -> stranger" { run greet; [ "$output" = "hello, stranger" ]; }
@test "greet: twice -> two lines, compared in one multi-line test kcov cannot place" {
    run bash -c 'source "$1"; greet a; greet b' _ /code/tests/fixture/src/greet.bash
    [[ "$output" == $'hello, a\nhello, b' ]]
}
@test "greet: child bash under set -u -> works when traced" {
    # shellcheck disable=SC2016  # the script runs in the child bash
    run --separate-stderr bash -euo pipefail -c 'source "$1"; greet x' _ /code/tests/fixture/src/greet.bash
    [ "$status" -eq 0 ]
    [ "$stderr" = "" ]
}
