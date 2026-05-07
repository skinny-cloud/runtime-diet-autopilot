# Context Surfaces Checklist

Claude Code cost and limit pressure can come from more than the prompt you just typed.

This checklist focuses on visible surfaces you can inspect.

---

## Always-Loaded Or Frequently-Loaded Text

- Project `CLAUDE.md`
- User/global `CLAUDE.md`
- `AGENTS.md`
- Rules folders
- Memory files
- Long standing instructions
- Repeated pasted skill prompts

Ask:

> Does this file need to be carried into every task?

---

## Tool And MCP Surface

- MCP servers
- Plugin tools
- Browser tools
- Gmail/Drive/Calendar connectors
- Database tools
- Custom local tools

Ask:

> Does this session need every available tool, or just the few required for the job?

---

## Hooks And Automation

- Prompt-submit hooks
- Session-start hooks
- Tool-use hooks
- Stop hooks
- Heartbeat/loop injections

Ask:

> Does this hook emit model-visible text? How often?

---

## Conversation Ancestry

- Long-lived sessions
- Resumed old branches
- Multi-day agent loops
- Repeated failures while unauthenticated
- Large tool outputs left in history

Ask:

> Am I on a clean session, or did I just inherit yesterday's token debt?

---

## Project Data

- Large docs directories
- Generated reports
- Test logs
- Build output
- Vendored dependencies
- Transcripts
- PDFs converted to text

Ask:

> Did I ask the model to inspect only what it needs, or did I invite it into the whole attic?

