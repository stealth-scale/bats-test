#!/usr/bin/env bats
load ../src/greet
@test "greet: name -> greets it" { run greet world; [ "$output" = "hello, world" ]; }
@test "greet: no name -> stranger" { run greet; [ "$output" = "hello, stranger" ]; }
@test "greet: child bash under set -u -> works when traced" {
    # shellcheck disable=SC2016  # the script runs in the child bash
    run --separate-stderr bash -euo pipefail -c 'source "$1"; greet x' _ /code/tests/fixture/src/greet.bash
    [ "$status" -eq 0 ]
    [ "$stderr" = "" ]
}
