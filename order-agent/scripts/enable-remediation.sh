#!/usr/bin/env bash
#
# enable-remediation.sh — T2, WRITE (dry-run stub).
# Would set order.remediation.enabled=true on the deployment via SPRING_APPLICATION_JSON,
# which creates a ConfigMap and triggers a rolling pod restart.
#
# Usage:
#   ./enable-remediation.sh <deployment> <namespace> <context> [--confirm]
# Example:
#   ./enable-remediation.sh service-connector-order master-connectors dev --confirm
#
# WITHOUT --confirm it only PRINTS the plan and exits 10 (needs human approval).
# WITH --confirm a real version would run:  ./patch-deployment.sh <dep> <ns> config.json <ctx>
# In this Level-2 build it is a dry run: nothing touches the cluster.
set -euo pipefail

DEP="${1:?deployment name required}"
NS="${2:?namespace required}"
CTX="${3:?kube context required}"
CONFIRM="${4:-}"

CONFIG='{"order.remediation.enabled":"true"}'

echo "── enable_remediation (T2 write) ─────────────────────────────"
echo "deployment : $DEP"
echo "namespace  : $NS"
echo "context    : $CTX"
echo "config     : $CONFIG"
echo "effect     : creates ConfigMap custom-spring-config-$DEP, adds envFrom, rolling pod restart"

if [ "$CONFIRM" != "--confirm" ]; then
  echo
  echo "NOT CONFIRMED — this is a T2 write that restarts pods."
  echo "A human must approve. Re-run with --confirm to proceed."
  exit 10   # 10 = awaiting human approval
fi

echo
echo "[DRY RUN] would execute: ./patch-deployment.sh $DEP $NS config.json $CTX"
echo "[DRY RUN] no change made to the cluster in this Level-2 build."
exit 0
