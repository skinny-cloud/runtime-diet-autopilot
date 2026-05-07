# Session Hygiene Playbook

The goal is not to make Claude Code weak. The goal is to stop carrying stale context into work that does not need it.

---

## Use Fresh Sessions For New Work

When the task changes meaningfully, start clean.

Good fresh-session candidates:

- Switching projects.
- Moving from brainstorming to implementation.
- Moving from implementation to review.
- After a large failed tool run.
- After authentication/runtime failures.
- After a long overnight loop.

---

## Use `/clear` Between Unrelated Tasks

Use `/clear` when the next task does not need the previous task's details.

Example:

```text
/clear
Read README.md and the current issue only. Do not load old conversation context.
```

---

## Use `/compact` With Explicit Preservation

Use `/compact` when continuity matters but raw history is too large.

Example preservation instruction:

```text
/compact
Preserve: objective, files changed, tests run, unresolved blockers, next exact command.
Discard: raw logs, repeated failed attempts, obsolete exploration.
```

---

## Externalize State

Keep durable state in files, not in the model window:

- `NEXUS.md` or equivalent project dashboard.
- Decision records.
- Handoff notes.
- Test results.
- Git commits.
- Small context primer.

Then new sessions can recover from durable artifacts instead of raw transcript history.

---

## Shrink Always-Loaded Instructions

Long instructions are useful until they become tax.

Move details into:

- task-specific skill files;
- referenced docs;
- templates;
- checklists;
- short command wrappers.

Keep always-loaded files focused on identity, safety, and essential operating rules.

---

## Treat Tools As A Budget

Every tool surface can add schemas, instructions, or hidden routing overhead.

Before an expensive session, ask:

> Which tools does this task actually need?

Disable or avoid unrelated tool contexts where your environment allows it.

