#!/usr/bin/env bats
load ../src/lines
setup() { bats_require_minimum_version 1.5.0; }
@test "lines::string -> three lines" { run lines::string; [ "${#lines[@]}" -eq 3 ]; }
@test "lines::program -> exit 0" { run lines::program; [ "$status" -eq 0 ]; }
@test "lines::case a -> a" { run lines::case a; [ "$output" = a ]; }
@test "lines::case b -> other" { run lines::case b; [ "$output" = other ]; }
@test "lines::loop_redirect -> counts two lines" { run lines::loop_redirect $'x\ny'; [ "$output" = 2 ]; }
@test "lines::loop_pipe -> exit 0" { run lines::loop_pipe; [ "$status" -eq 0 ]; }
@test "lines::assignment -> two lines" { run lines::assignment; [ "${#lines[@]}" -eq 2 ]; }
@test "lines::test -> yes" { run lines::test x; [ "$output" = yes ]; }
@test "lines::rule -> the rule, then after" {
    run lines::rule
    [[ "$output" == *====$'\n'after ]]
}
