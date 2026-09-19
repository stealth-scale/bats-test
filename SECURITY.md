# Security policy

## Supported versions

The tags published from `main` are supported.

## Reporting a vulnerability

Report a vulnerability through GitHub's private vulnerability reporting on this repository,
under its Security tab. Do not open a public issue. We acknowledge a report within three
working days and publish a fix before any disclosure.

## Privileges at run time

The consumers' Makefiles run the image as the calling user, with every capability dropped,
without network, with the checkout mounted read-only and only the coverage directory
writable. kcov's bash engine needs no ptrace capability. The ELF engine, which kcov would use for a
binary, is not needed and not granted.
