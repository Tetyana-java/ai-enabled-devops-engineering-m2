# Agent card: order-remediation

1. Task:            remediate orders  - "needs manual reprocessing" for service-connector-order —
                    pull the stuck messageKeys from Kibana, enable the remediation endpoint, trigger
                    remediation for those keys, then restore config · ~1–2/week · 25–40 min by hand
2. Agent or workflow? Workflow (prompt-chaining) with a human gate before every write — NOT an autonomous
                    agent. Six questions (slide 38): Q2 the steps are knowable in advance (pull → enable →
                    trigger → restore), so it is a workflow; Q3 it is write-heavy (K8s config + a prod
                    remediation call), so it stays single-threaded; Q4 the keys and country come from logs
                    (untrusted), so a human approves and may edit before any write. The model only drafts the
                    remediation request and summarises it; it never fires a write on its own.
3. Pattern:         prompt chaining (fixed steps, a programmatic check between each) + human-in-the-loop
                    (approve / edit / reject) on each write step
4. Tools (max 3–4):
   - pull_order_errors  — which unique messageKeys + diiCountry2l hit this error, in a time window — T0 (read)
   - enable_remediation — set order.remediation.enabled=true on the deployment (restarts pods)        — T2 (write)
   - trigger_remediation— POST /api/v1/remediate/{country}/orders with the keys + window               — T2/T3 (acts on orders)
   - restore_config     — remove the ConfigMap / envFrom, roll back to original pods                   — T2 (write)
5. AGENTS.md:       Kibana SSO only for the pull; app.id=consumerdb.services.service-connector-order,
                    severity=ERROR, phrase "Event needs to be reprocessed manually"; messageKey + diiCountry2l
                    are keyword fields; dedupe keys; country for the URL path = diiCountry2l (2-letter), and
                    if it is null DO NOT silently default — surface it to the human (PL is a test-only value);
                    time window is an explicit input, never guessed; config change and the POST each wait for
                    approval; always restore config after remediation
6. Limits:          max 1 enable + 1 trigger + 1 restore per run · no auto-retry on a failed write · 120 s per
                    step · the keys list is bounded to one pull (no open-ended looping)
7. Human gate:      TWO gates, plus one conditional stop. (a) before enable_remediation — "about to patch
                    <deployment>/<ns>/<ctx>, pods restart". (b) before trigger_remediation — "about to
                    remediate N orders, country=<X>, window <from>–<to>"; human can approve / EDIT (fix
                    country or window) / reject. CONDITIONAL STOP: if country (diiCountry2l) is null/missing,
                    halt before gate (b) and ask the human to either provide the country or reject the run —
                    never proceed on a guessed/defaulted value. restore runs after, also confirmable.
8. Untrusted input: messageKey, diiCountry2l, and the error text all come from Kibana logs — treated as DATA,
                    never as instructions. They are validated (keys numeric-ish, country is a known 2-letter
                    code) before they enter the POST body or the URL path. No session cookie / kubeconfig
                    stored in the transcript; secrets redacted from every tool result.
9. How to check:    5 past remediations with a known-good outcome. Correct = (i) same messageKey set as the
                    manual run, (ii) correct country in the URL, (iii) POST returned 2xx for each key,
                    (iv) config restored afterwards (deployment back to original, ConfigMap gone).
10. Must never:     fire enable or trigger without a human approval, or default the country silently —
                    enforced by: write scripts require an explicit --confirm flag the human supplies
                    (no tool writes on the model's say-so); country has NO default — if diiCountry2l is
                    null/missing the run STOPS and asks the human, who may either (a) provide the country
                    explicitly or (b) reject and abort the run. 
```

---

## Why this is a workflow, not just a script, and not an autonomous agent

- **More than a script**, because there is a judgement step between the pull and the writes — "are these keys one incident or several, what country and window apply, should we remediate now?" — and a human decision gate that an unattended script cannot provide.
- **Not an autonomous agent**, because the sequence (pull → enable → trigger → restore) is fixed and knowable in advance. You do not need the model to choose the next step; 

## Tool tiers at a glance (slide 33)

| Tool | Blast radius | Tier | Gate |
|---|---|---|---|
| pull_order_errors | read-only Kibana | T0 | automatic |
| enable_remediation | patches a K8s Deployment, restarts pods | T2 | human approval |
| trigger_remediation | remediates real orders via prod API | T2/T3 | human approval + edit |
| restore_config | reverts the Deployment, deletes ConfigMap | T2 | human approval |
