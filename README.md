# Claude Code Runtime Diet Autopilot

**One command. Know exactly what your Claude Code setup loads before you type anything.**

I was on git `main`. Claude was on a three-day session branch.  
That mistake cost 389,169 tokens at session start before I typed a real prompt.

Most of that load was invisible to me. This script makes it visible.

---

## What it does

Scans your local Claude Code context surfaces — read-only, nothing written, nothing sent anywhere:

- `~/.claude/projects/` transcript store
- `CLAUDE.md` files
- Hooks, skills, rules
- Recent session branches

Outputs a **Runtime Diet Card**: your visible context load, ranked by size, with a next-session hygiene rule generated for your specific setup.

```
$ bash scripts/claude-runtime-diet-report.sh .

Scanning context surfaces...

~/.claude/projects/     768 MB    (~192K tokens)
CLAUDE.md               6.9 KB    (~1.7K tokens)
.claude/hooks/          20 hooks  (~8K tokens)
Session branch (3d)     32 MB     (~8M tokens)  ← FAT

Diet card saved → .claude/runtime-diet-card.md
```

---

## Install

No install. Download and run:

```bash
git clone https://github.com/skinny-cloud/runtime-diet-autopilot
bash scripts/claude-runtime-diet-report.sh /path/to/your/project
```

Or one-liner:

```bash
curl -sL https://skinny.cloud/diet.sh | bash
```

---

## What you get

- `scripts/claude-runtime-diet-report.sh` — one-command report generator
- `scripts/claude-runtime-static-baseline.sh` — read-only local baseline
- `docs/389k-case-study.md` — the real incident: how I burned 389K tokens before typing anything
- `docs/context-surfaces-checklist.md` — every surface that can inflate your context
- `docs/session-hygiene-playbook.md` — `/clear`, `/compact`, fresh sessions, MCP discipline
- `templates/runtime-diet-card.md` — your generated card (share-safe, no secrets)

---

## Privacy

Read-only. Nothing leaves your machine. No account, no email, no telemetry by default.

Optional: `RUNTIME_DIET_TELEMETRY=1` sends an anonymous install_id + audit-completed event. That's it.

---

## The receipts

Across 15 active AI projects, context discipline alone cut Claude costs by **$750/month**.

The agents that win aren't the ones with the most context.  
They're the ones that know what not to load.

→ **[skinny.cloud](https://skinny.cloud)** — lean AI ops, real receipts, no fluff.

---

## License

Apache-2.0. Use it, fork it, build on it.
