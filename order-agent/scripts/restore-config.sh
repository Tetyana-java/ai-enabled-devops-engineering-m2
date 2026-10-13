#!/usr/bin/env bash
#
# restore-config.sh — T2, WRITE (dry-run stub).
# Would revert the deployment: remove envFrom, delete the ConfigMap, roll back to original pods.
# Always run this after remediation so the remediation flag is not left enabled.
#
# Usage:
#   ./restore-config.sh <deployment> <namespace> <context> [--confirm]
# Example:
#   ./restore-config.sh service-connector-order master-connectors dev --confirm
#
# WITHOUT --confirm it only PRINTS the plan and exits 10 (needs human approval).
# WITH --confirm a real version would run:  ./restore-deployment.sh <dep> <ns> <ctx>
# In this Level-2 build it is a dry run: nothing touches the cluster.
set -euo pipefail

DEP="${1:?deployment name required}"
NS="${2:?namespace required}"
CTX="${3:?kube context required}"
CONFIRM="${4:-}"

echo "── restore_config (T2 write) ─────────────────────────────────"
echo "deployment : $DEP"
echo "namespace  : $NS"
echo "context    : $CTX"
echo "effect     : removes envFrom, deletes ConfigMap custom-spring-config-$DEP, rolling pod restart"

if [ "$CONFIRM" != "--confirm" ]; then
  echo
  echo "NOT CONFIRMED — this is a T2 write that restarts pods."
  echo "A human must approve. Re-run with --confirm to proceed."
  exit 10   # 10 = awaiting human approval
fi

echo
echo "[DRY RUN] would execute: ./restore-deployment.sh $DEP $NS $CTX"
echo "[DRY RUN] no change made to the cluster in this Level-2 build."
exit 0
