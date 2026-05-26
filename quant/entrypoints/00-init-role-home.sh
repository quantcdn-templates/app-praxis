#!/bin/sh
# Praxis role-home preparation. Runs as the container user (node, UID 1000).
#
# Responsibilities (intentionally narrow):
#  - Ensure /role exists and is writable by the runtime user.
#  - Set a default git identity for OPERATOR-attributed commits when none is
#    configured.
#  - Surface a one-line summary to stdout so deploy logs make it obvious which
#    state the volume booted in (fresh / existing).
#
# Non-responsibilities:
#  - Cloning a remote source repo (this template's flow is wizard-driven).
#  - Initialising the git repo itself — dashboard/src/lib/audit.ts auto-inits
#    on first mutation. Pre-initialising here would land an empty baseline
#    commit before the wizard, muddling the role's history.
#  - Migrating data. EFS persistence is the operator's contract.

set -eu

ROLE_HOME="${PRAXIS_ROLE_HOME:-/role}"

if [ ! -d "$ROLE_HOME" ]; then
  echo "praxis: ERROR /role is not mounted — configure a persistent volume at $ROLE_HOME" >&2
  exit 1
fi

if [ ! -w "$ROLE_HOME" ]; then
  echo "praxis: ERROR $ROLE_HOME is not writable by uid $(id -u)" >&2
  exit 1
fi

# Operator git identity. dashboard/src/lib/audit.ts inits the repo and makes the
# first commit on the initial wizard submit, so an identity must resolve *before*
# .git exists — otherwise that commit fails with "Author identity unknown" and
# /setup returns a 500.
#
# Scope matters: this hook runs as root, but the app base entrypoint drops
# privileges (`exec gosu node`) so the server — and thus that first commit —
# runs as `node`. A --global config would land in root's HOME, which node never
# reads. Use --system (/etc/gitconfig, read by every user) so node picks it up.
# Once .git exists, also pin a per-repo identity (read regardless of user) so the
# volume carries it forward across redeploys. Only set each scope when absent.
if [ -z "$(git config --system user.name || true)" ]; then
  git config --system user.name  "${PRAXIS_OPERATOR_NAME:-Quant Operator}"
  git config --system user.email "${PRAXIS_OPERATOR_EMAIL:-operator@quant.cloud}"
fi

if [ -d "$ROLE_HOME/.git" ]; then
  cd "$ROLE_HOME"
  # --local so the merged-in system fallback above doesn't mask an unset repo.
  if [ -z "$(git config --local user.name || true)" ]; then
    git config user.name  "${PRAXIS_OPERATOR_NAME:-Quant Operator}"
    git config user.email "${PRAXIS_OPERATOR_EMAIL:-operator@quant.cloud}"
  fi
fi

# Boot summary — one line for the deploy log.
if [ -f "$ROLE_HOME/persona.md" ]; then
  echo "praxis: role-home seeded — $(ls "$ROLE_HOME" | wc -l | tr -d ' ') entries"
else
  echo "praxis: role-home empty — operator should visit /setup to seed"
fi
