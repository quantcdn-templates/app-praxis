#!/bin/sh
# Tests for quant/entrypoints/00-init-role-home.sh
#
# Runs the entrypoint in an isolated sandbox (its own system + global git config
# files via GIT_CONFIG_SYSTEM / GIT_CONFIG_GLOBAL) so it writes nowhere real.
# No Docker required:
#
#   sh test/test-init-role-home.sh
#
# Regression target: a fresh role-home (no .git) must end with a usable git
# identity so audit.ts's first commit succeeds — otherwise /setup returns 500.
# The identity must be set at *system* scope: the hook runs as root but the
# server (which makes that commit) runs as `node` via gosu, and node does not
# read root's --global config. Requires git >= 2.32 (GIT_CONFIG_SYSTEM).

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENTRYPOINT="$SCRIPT_DIR/../quant/entrypoints/00-init-role-home.sh"

[ -f "$ENTRYPOINT" ] || { echo "FAIL: entrypoint not found at $ENTRYPOINT" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

# Fresh isolated sandbox per case. GIT_CONFIG_SYSTEM/GIT_CONFIG_GLOBAL pin the
# system/global config files into the sandbox; HOME/XDG are redirected too so no
# host config leaks in or out.
new_sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home"
  export XDG_CONFIG_HOME="$SANDBOX/xdg"
  export GIT_CONFIG_SYSTEM="$SANDBOX/systemconfig"
  export GIT_CONFIG_GLOBAL="$SANDBOX/globalconfig"
  export ROLE_HOME="$SANDBOX/role"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$ROLE_HOME"
  : > "$GIT_CONFIG_SYSTEM"
  : > "$GIT_CONFIG_GLOBAL"
}

run_entrypoint() {
  PRAXIS_ROLE_HOME="$ROLE_HOME" \
  PRAXIS_OPERATOR_NAME="${OP_NAME:-Test Operator}" \
  PRAXIS_OPERATOR_EMAIL="${OP_EMAIL:-op@test}" \
    sh "$ENTRYPOINT" >/dev/null
}

# --- Case 1: fresh role-home (no .git) gets a SYSTEM identity (what node reads),
# and a first commit (what audit.ts does) then succeeds. This is the actual bug. ---
new_sandbox
OP_NAME="Fresh Operator" OP_EMAIL="fresh@test" run_entrypoint
[ "$(git config --system user.name)" = "Fresh Operator" ] \
  || fail "fresh volume: system user.name not set (a --global-only fix is unread by node)"
[ "$(git config --system user.email)" = "fresh@test" ] \
  || fail "fresh volume: system user.email not set"
# Simulate audit.ts: init repo in role-home and commit with no per-repo identity.
( cd "$ROLE_HOME" && git init -q && echo seed > persona.md && git add persona.md \
    && git commit -qm "seed" ) || fail "fresh volume: first commit failed (the 500)"
pass "fresh role-home seeds and first commit succeeds (system scope)"

# --- Case 2: a pre-existing system identity is never overwritten. ---
new_sandbox
git config --system user.name  "Existing Person"
git config --system user.email "existing@test"
OP_NAME="Should Not Win" OP_EMAIL="nope@test" run_entrypoint
[ "$(git config --system user.name)" = "Existing Person" ] \
  || fail "idempotency: system user.name was overwritten"
[ "$(git config --system user.email)" = "existing@test" ] \
  || fail "idempotency: system user.email was overwritten"
pass "existing system identity preserved"

# --- Case 3: when .git exists, a per-repo identity is written so the volume
# carries it forward — even though a system fallback is already present. ---
new_sandbox
git config --system user.name  "System Person"
git config --system user.email "system@test"
( cd "$ROLE_HOME" && git init -q )   # .git exists, no per-repo identity
OP_NAME="Repo Operator" OP_EMAIL="repo@test" run_entrypoint
[ "$(git -C "$ROLE_HOME" config --local user.name)" = "Repo Operator" ] \
  || fail "carry-forward: per-repo user.name not set on existing .git"
[ "$(git -C "$ROLE_HOME" config --local user.email)" = "repo@test" ] \
  || fail "carry-forward: per-repo user.email not set on existing .git"
pass "per-repo identity written on existing .git"

echo "All tests passed."
