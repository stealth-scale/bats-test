#!/usr/bin/env bats
load ../src/greet
setup() { bats_require_minimum_version 1.5.0; }
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
