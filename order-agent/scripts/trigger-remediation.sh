#!/usr/bin/env bash
#
# trigger-remediation.sh — T2/T3, WRITE (dry-run stub).
# Would POST to the remediation endpoint to reprocess the stuck orders:
#   POST https://service-connector-order.<envDomain>/api/v1/remediate/<COUNTRY>/orders
#   body: { "orderNums": [<keys>], "from": "<from>", "to": "<to>" }
#
# Usage:
#   ./trigger-remediation.sh <envDomain> <COUNTRY> <from> <to> <keysCsvFile> [--confirm]
# Example:
#   ./trigger-remediation.sh dev.example.com PL \
#       2026-09-22T10:20:00+02:00 2026-09-22T10:32:00+02:00 keys.txt --confirm
#
# COUNTRY has NO default. If you pass 'null' or leave it empty the run STOPS and asks a human
# to provide the country or reject — PL is never auto-filled (it is a test-only value).
# WITHOUT --confirm it only PRINTS the request and exits 10 (needs human approval).
# In this Level-2 build it is a dry run: no POST is sent.
set -euo pipefail

ENV_DOMAIN="${1:?envDomain required}"
COUNTRY="${2:-}"
FROM="${3:?from timestamp required}"
TO="${4:?to timestamp required}"
KEYS_FILE="${5:?file with one messageKey per line required}"
CONFIRM="${6:-}"

# ── country stop-and-ask: never guess, never default ──────────────────────────
if [ -z "$COUNTRY" ] || [ "$COUNTRY" = "null" ] || [ "$COUNTRY" = "NULL" ]; then
  echo "STOP: country (diiCountry2l) is missing/null." >&2
  echo "A human must either provide the country explicitly, or reject this run." >&2
  echo "PL is NOT auto-filled — it is a test-only value." >&2
  exit 11   # 11 = stopped, needs country from human
fi
# basic validation: a two-letter uppercase code
if ! printf '%s' "$COUNTRY" | grep -Eq '^[A-Z]{2}$'; then
  echo "STOP: country '$COUNTRY' is not a 2-letter uppercase code." >&2
  exit 11
fi
[ -f "$KEYS_FILE" ] || { echo "ERROR: keys file not found: $KEYS_FILE" >&2; exit 1; }

# Build the orderNums JSON array from the keys file (keys treated as DATA, validated).
ORDER_NUMS=$(grep -E '.' "$KEYS_FILE" | jq -R . | jq -s -c .)
N=$(printf '%s' "$ORDER_NUMS" | jq 'length')
URL="https://service-connector-order.$ENV_DOMAIN/api/v1/remediate/$COUNTRY/orders"
BODY=$(jq -n --argjson keys "$ORDER_NUMS" --arg from "$FROM" --arg to "$TO" \
  '{orderNums:$keys, from:$from, to:$to}')

echo "── trigger_remediation (T2/T3 write) ─────────────────────────"
echo "url        : POST $URL"
echo "country    : $COUNTRY"
echo "orders     : $N"
echo "window     : $FROM  →  $TO"
echo "body       :"
echo "$BODY" | jq .

if [ "$CONFIRM" != "--confirm" ]; then
  echo
  echo "NOT CONFIRMED — this remediates $N real orders in $COUNTRY."
  echo "A human must approve (or EDIT country/window, or reject). Re-run with --confirm to proceed."
  exit 10   # 10 = awaiting human approval
fi

echo
echo "[DRY RUN] would POST the body above to $URL"
echo "[DRY RUN] no request sent in this Level-2 build."
exit 0
