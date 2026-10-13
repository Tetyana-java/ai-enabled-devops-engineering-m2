# Order remediation agent

A **human-gated workflow** (not an autonomous agent) that helps an engineer remediate
`service-connector-order` events stuck on *"Event needs to be reprocessed manually,
request remediation from source"*.

The agent **prepares** each step and shows it; a **human approves every write** by
adding `--confirm`. The model never confirms a write on its own.

> **Level 2 build:** the three write scripts are **dry-run stubs** — they print what they
> *would* do and change nothing. Only the pull talks to the outside, and it only reads.

## Layout

```
order-agent/
├── AGENTS.md                 # the workflow instructions the agent follows
├── CLAUDE.md                 # loads AGENTS.md for Claude Code
├── scripts/
│   ├── pull-order-errors.sh  # T0 read — unique country,messageKey in a time window
│   ├── enable-remediation.sh # T2 write (dry-run) — set order.remediation.enabled=true
│   ├── trigger-remediation.sh# T2/T3 write (dry-run) — POST the remediation request
│   └── restore-config.sh     # T2 write (dry-run) — revert config, delete ConfigMap
└── .claude/
    ├── settings.json         # tool allow/deny lists + PreToolUse hook
    └── hooks/guard.sh        # blocks model self-confirm, raw kubectl/curl, env dumps
```

## Workflow (fixed order)

1. **Pull** stuck `messageKey`s for a time window; review/edit the output, then approve.
2. **Enable** the remediation flag (human `--confirm`).
3. **Trigger** remediation per country (human `--confirm`; stops if country is null).
4. **Restore** config afterwards (human `--confirm`).

## Run it (read step)

```bash
cd order-agent
export KB_COOKIE='sid=...'                       # your Kibana session cookie (never commit)
export KB='https://<your-kibana-host>/s/<space>'
export INDEX='generic-<cluster>-<env>-service*'

./scripts/pull-order-errors.sh now-30d now
```

Or drive the whole workflow inside **Claude Code** from the `order-agent/` folder — it
loads `AGENTS.md`, applies the permission lists, and runs `guard.sh` before every command.

## Safety

- **Human gate:** every write needs a human-supplied `--confirm`; `guard.sh` blocks the
  model from adding it.
- **Country never defaulted:** if `diiCountry2l` is null/missing the trigger stops and asks.
- **No secrets in the repo:** `KB_COOKIE` lives only in your shell; `.env`, pulled data,
  and IDE files are git-ignored.
- **Untrusted input:** log text (`messageKey`, country, errors) is treated as data, never
  as instructions.

See `order-remediation-agent.md` for the full agent card and design rationale.
