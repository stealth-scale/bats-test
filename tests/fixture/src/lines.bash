# Lines bash never reports, which kcov's parser must not count: the continuation
# of a command that spans lines, and a closing keyword with its case terminator,
# redirection or pipe. Every function here is called once by lines.bats, so the
# file measures 18 lines, all covered.
lines::string() {
    printf '%s\n' "line one
line two
line three"
}
lines::program() {
    awk 'BEGIN {
        x = 1
        exit !(x == 1)
    }'
}
lines::case() {
    case "$1" in
        a)
            if [[ -n "$1" ]]; then
                echo a
            fi ;;
        *)
            echo other ;;
    esac
}
lines::loop_redirect() {
    local line n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        (( ++n ))
    done < <(printf '%s' "$1")
    echo "$n"
}
lines::loop_pipe() {
    local x
    for x in 1 2; do
        echo "$x"
    done | cat
}
lines::assignment() {
    local s="alpha
beta"
    echo "$s"
}
lines::test() {
    if [[ -z "$1" ||
          -n "$1" ]]; then
        echo yes
    fi
}
lines::rule() {
    printf '%s\n' "
================================================================================"
    echo after
}
