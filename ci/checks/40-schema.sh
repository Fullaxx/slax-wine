#!/bin/sh
# stages: pre-commit pre-push ci
# desc: yamllint + JSON Schema validation of our recipes and profiles.
#
# Adapted from slax-kitchen @ b4eb25bada4753a014e7e9c75a98a25874a92837 (ci/checks/40-schema.sh). Two differences: the
# scope is ours only (this repo has no compat/ or schema/ of its own), and the
# validator comes from the submodule -- lib/validate.py resolves its schema directory
# relative to its own location, so it works from here without configuration.
. "$(dirname "$0")/../lib.sh"

VALIDATE="$REPO_ROOT/vendor/slax-kitchen/lib/validate.py"
have yamllint || warn "yamllint not installed - skipping lint half"
# This gate already refused without python3, but only by accident: lib/validate.py's
# `#!/usr/bin/env python3` cannot exec, so the `|| fail` below fired once per file, saying
# "/usr/bin/env: 'python3': No such file or directory" -- 47 of them upstream on
# 2026-09-20, for one cause. Said once now, here, before the file list is built -- which
# also costs the yamllint half on such a machine, and that is the trade: the gate is
# refusing either way. (Upstream's wording names compat/ too; this repo has neither
# compat/ nor schema/ of its own, which is difference one in the header.)
require_python3 "no recipe or profile is schema-checked at all"

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
