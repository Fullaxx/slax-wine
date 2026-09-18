#!/bin/sh
# stages: pre-commit pre-push ci
# desc: yamllint + JSON Schema validation of our recipes and profiles.
#
# Adapted from slax-kitchen @ 9776a9042394deac25638847269154eb5cebc9ca (ci/checks/40-schema.sh). Two differences: the
# scope is ours only (this repo has no compat/ or schema/ of its own), and the
# validator comes from the submodule -- lib/validate.py resolves its schema directory
# relative to its own location, so it works from here without configuration.
. "$(dirname "$0")/../lib.sh"

VALIDATE="$REPO_ROOT/vendor/slax-kitchen/lib/validate.py"
have yamllint || warn "yamllint not installed - skipping lint half"

check_files_nl | grep -E '^(recipes|profiles)/.*\.ya?ml$' > /tmp/.slaxwine-yaml.$$ || true

if [ -s /tmp/.slaxwine-yaml.$$ ]; then
    if have yamllint; then
        while IFS= read -r f; do
            yamllint -f parsable -c "$REPO_ROOT/ci/yamllint.yaml" "$REPO_ROOT/$f" || fail "yamllint: $f"
        done < /tmp/.slaxwine-yaml.$$
    fi
    if [ -x "$VALIDATE" ]; then
        while IFS= read -r f; do
            "$VALIDATE" "$REPO_ROOT/$f" || fail "schema: $f"
        done < /tmp/.slaxwine-yaml.$$
    else
        note "vendor/slax-kitchen not checked out - schema half skipped"
    fi
fi
rm -f /tmp/.slaxwine-yaml.$$
check_result
