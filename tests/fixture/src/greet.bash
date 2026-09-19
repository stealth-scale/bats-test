# A small library for the image's own tests. One branch is never called.
greet() {
    local name="${1-}"
    if [[ -z "$name" ]]; then
        printf 'hello, stranger\n'
    else
        printf 'hello, %s\n' "$name"
    fi
}
never_called() {
    printf 'this line is not covered\n'
}
