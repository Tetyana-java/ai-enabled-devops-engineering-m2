#!/usr/bin/env bash
#
# pull-order-errors.sh — T0, READ ONLY.
# Pull unique (diiCountry2l, messageKey) for service-connector-order events that are
# stuck on "Event needs to be reprocessed manually, request remediation from source"
# via the Kibana Discover search endpoint (/internal/search/ese). SSO cookie only.
#
# In these indices messageKey / diiCountry2l are NOT indexed as structured fields;
# they live inside the free-text `log.message` body. So this tool runs a hits search
# (not a composite agg), pages with search_after, and regexes the two values out of
# each log.message. Country is emitted exactly as logged (literal 'null' if null) —
# never defaulted here.
#
# Usage:
#   export KB_COOKIE='sid=...'                 # whole Cookie header value (don't commit it)
#   ./pull-order-errors.sh [GTE] [LTE]
#
# Env overrides:
#   KB         Kibana base (default PRD/dcev1)
#   INDEX      index pattern (default generic-dcev1-prd-service*; use *qa1* for STG)
#   TZ_OFFSET  timezone for local GTE/LTE (default +00:00; GTE/LTE with Z stay UTC)
#
# Output: CSV "diiCountry2l,messageKey" on stdout (dedup with | sort -u).
# This is the only tool that talks to the outside, and it only READS.
set -euo pipefail

KB="${KB:-https://<your-kibana-host>/s/<space>}"
URL="$KB/internal/search/ese"
INDEX="${INDEX:-generic-dcev1-prd-service*}"
: "${KB_COOKIE:?set KB_COOKIE to your Kibana session cookie}"

GTE="${1:-now-7d}"
LTE="${2:-now}"
PHRASE="Event needs to be reprocessed manually, request remediation from source"
TZ_OFFSET="${TZ_OFFSET:-+00:00}"
PAGE=5000
AFTER="null"   # search_after cursor (JSON array), null on first page
ROWS=""        # accumulates "country,messageKey" rows across all pages

req() {
  curl -s "$URL" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -H "elastic-api-version: 1" \
    -H "kbn-version: 9.3.8" \
    -H "x-elastic-internal-origin: Kibana" \
    -H "Cookie: $KB_COOKIE" \
    --data "$1"
}

while :; do
  BODY=$(jq -n \
    --arg idx "$INDEX" --arg gte "$GTE" --arg lte "$LTE" --arg phrase "$PHRASE" \
    --arg tz "$TZ_OFFSET" --argjson page "$PAGE" --argjson after "$AFTER" '
    {
      params: {
        index: $idx,
        wait_for_completion_timeout: "60s",
        body: ({
          size: $page,
          track_total_hits: true,
          _source: false,
          fields: [ "log.message" ],
          sort: [
            { "@timestamp": { order: "asc", format: "strict_date_optional_time" } },
            { "_shard_doc": { order: "asc" } }
          ],
          query: { bool: {
            filter: [
              { range: { "@timestamp": { format:"strict_date_optional_time", gte:$gte, lte:$lte, time_zone:$tz } } },
              { match_phrase: { "app.id.keyword": "consumerdb.services.service-connector-order" } },
              { match_phrase: { "log.severity.keyword": "ERROR" } },
              { multi_match: { type: "phrase", query: $phrase, lenient: true } }
            ]
          } }
        } + ($after | if .==null then {} else {search_after:$after} end))
      }
    }')

  RESP=$(req "$BODY")

  if ! echo "$RESP" | jq -e '.' >/dev/null 2>&1; then
    echo "ERROR: non-JSON response (cookie missing/expired?):" >&2
    echo "$RESP" | head -c 300 >&2; echo >&2
    exit 1
  fi
  if echo "$RESP" | jq -e 'has("statusCode") or has("error")' | grep -q true; then
    echo "ERROR: Kibana returned an error:" >&2
    echo "$RESP" | jq -c '{statusCode,error,message}' >&2
    exit 1
  fi
  if ! echo "$RESP" | jq -e '.rawResponse.hits.hits' >/dev/null 2>&1; then
    echo "ERROR: no hits in response:" >&2
    echo "$RESP" | head -c 500 >&2; echo >&2
    exit 1
  fi

  # messageKey / diiCountry2l are embedded in the free-text log.message body.
  # Extract both per hit; collect "country,messageKey". Country is logged as literal
  # 'null' when absent — pass it through unchanged (never defaulted here).
  PAGE_ROWS=$(echo "$RESP" | jq -r '
    .rawResponse.hits.hits[]
    | ((.fields["log.message"] // [""]) | if type=="array" then .[0] else . end) as $m
    | ( ($m | capture("messageKey:\\s*(?<k>[^\\n]*?)\\s*(?:\\n|$)").k) // empty ) as $key
    | ( ($m | capture("diiCountry2l:\\s*(?<c>[^\\n]*?)\\s*(?:\\n|$)").c) // "null" ) as $country
    | select($key != "" and $key != null)
    | "\($country),\($key)"
  ')
  [ -n "$PAGE_ROWS" ] && ROWS+="$PAGE_ROWS"$'\n'

  # Advance the search_after cursor to the sort value of the last hit on this page.
  N=$(echo "$RESP" | jq '.rawResponse.hits.hits | length')
  AFTER=$(echo "$RESP" | jq -c '.rawResponse.hits.hits[-1].sort // null')
  { [ "$AFTER" = "null" ] || [ "$N" -lt "$PAGE" ]; } && break
done

# Emit unique rows only (dedup across all pages). Drop trailing blank line first.
printf '%s' "$ROWS" | sed '/^$/d' | sort -u
