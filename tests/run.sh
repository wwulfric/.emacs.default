#!/bin/sh
# Run each suite in a fresh Emacs, with state outside the user's configuration.
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/emacs-config-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
trap 'exit 1' HUP INT TERM
if [ "$#" -eq 0 ]; then
    set -- tests/*-tests.el
fi
status=0
index=0
for suite do
    index=$((index + 1))
    EMACS_TEST_HOME="$test_root/$index"
    export EMACS_TEST_HOME
    mkdir "$EMACS_TEST_HOME"
    "${EMACS:-emacs}" -Q --batch -l tests/bootstrap.el -l "$suite" \
        -f ert-run-tests-batch-and-exit || status=1
done
exit "$status"
