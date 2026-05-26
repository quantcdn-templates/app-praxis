#!/bin/sh
# Tests for quant/entrypoints/00-init-role-home.sh
#
# Runs the entrypoint in an isolated sandbox (its own HOME + GIT_CONFIG_GLOBAL)
# so `git config --global` writes nowhere real. No Docker required:
#
#   sh test/test-init-role-home.sh
#
# Regression target: a fresh role-home (no .git) must end with a usable git
# identity so audit.ts's first commit succeeds — otherwise /setup returns 500.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/../quant/entrypoints/00-init-role-home.sh"

[ -f "$ENTRYPOINT" ] || { echo "FAIL: entrypoint not found at $ENTRYPOINT" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

# Fresh isolated sandbox per case. GIT_CONFIG_GLOBAL pins --global to a sandbox
# file; HOME/XDG are redirected too so no host config leaks in or out.
new_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$SANDBOX/xdg"
  export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
  export ROLE_HOME="$SANDBOX/role"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$ROLE_HOME"
  : > "$GIT_CONFIG_GLOBAL"
}

run_entrypoint() {
  PRAXIS_ROLE_HOME="$ROLE_HOME" \
  PRAXIS_OPERATOR_NAME="${OP_NAME:-Test Operator}" \
  PRAXIS_OPERATOR_EMAIL="${OP_EMAIL:-op@test}" \
    sh "$ENTRYPOINT" >/dev/null
}

# --- Case 1: fresh role-home (no .git) gets a global identity, and a first
# commit (what audit.ts does) then succeeds. This is the actual bug. ---
new_sandbox
OP_NAME="Fresh Operator" OP_EMAIL="fresh@test" run_entrypoint
[ "$(git config --global user.name)" = "Fresh Operator" ] \
  || fail "fresh volume: global user.name not set"
[ "$(git config --global user.email)" = "fresh@test" ] \
  || fail "fresh volume: global user.email not set"
# Simulate audit.ts: init repo in role-home and commit with no per-repo identity.
( cd "$ROLE_HOME" && git init -q && echo seed > persona.md && git add persona.md \
    && git commit -qm "seed" ) || fail "fresh volume: first commit failed (the 500)"
pass "fresh role-home seeds and first commit succeeds"

# --- Case 2: a pre-existing global identity is never overwritten. ---
new_sandbox
git config --global user.name  "Existing Person"
git config --global user.email "existing@test"
OP_NAME="Should Not Win" OP_EMAIL="nope@test" run_entrypoint
[ "$(git config --global user.name)" = "Existing Person" ] \
  || fail "idempotency: global user.name was overwritten"
[ "$(git config --global user.email)" = "existing@test" ] \
  || fail "idempotency: global user.email was overwritten"
pass "existing global identity preserved"

# --- Case 3: when .git exists, a per-repo identity is written so the volume
# carries it forward — even though a global fallback is already present. ---
new_sandbox
git config --global user.name  "Global Person"
git config --global user.email "global@test"
( cd "$ROLE_HOME" && git init -q )   # .git exists, no per-repo identity
OP_NAME="Repo Operator" OP_EMAIL="repo@test" run_entrypoint
[ "$(git -C "$ROLE_HOME" config --local user.name)" = "Repo Operator" ] \
  || fail "carry-forward: per-repo user.name not set on existing .git"
[ "$(git -C "$ROLE_HOME" config --local user.email)" = "repo@test" ] \
  || fail "carry-forward: per-repo user.email not set on existing .git"
pass "per-repo identity written on existing .git"

echo "All tests passed."
