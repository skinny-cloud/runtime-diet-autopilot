# Case Study: The 389K Startup Burn

This is a sanitized case study from a long-running Claude Code setup. The numbers below are not a benchmark and they are not a claim about every Claude Code installation. They are a record of one failure mode I ran into: the prompt I could see was tiny, but the session state around it was not.

---

## What happened

I had a Chief-of-Staff style Claude Code session that had been alive too long. It had survived project switches, governance loops, failed tool calls, authentication problems, and several rounds of "just resume where we left off." From the outside I was on a normal git branch. From the model's point of view, the conversation branch was carrying days of accumulated state.

The immediate trigger was mundane: after an auth/runtime problem, I restarted the lane and typed a small recovery prompt.

```text
Welcome back.
```

That looked like a two-word prompt. It was not a two-word context event. The first successful expensive-model response after the restart created a large prompt cache before the real work began.

The line that made me stop was:

```text
389,169 cache-creation input tokens
```

The useful lesson was not "Claude is expensive" or "large context is bad." The lesson was narrower: a reused agent session can keep carrying invisible load long after the visible task has changed.

---

## The bill

The retained billing evidence for this write-up is the cache-creation input-token line above: 389,169 tokens on the first successful response after the restart. That was the alarm because cache creation is paid work done before the answer exists.

I am not publishing a full dollar breakdown here because I did not preserve the surrounding billing lines with enough confidence to make that honest. The prompt-input, cache-read, and output-token lines from that exact response are not in the surviving artifact. The exact model identifier also is not preserved in a form I am comfortable publishing as a fact. In other words: I can substantiate the cache-creation line; I cannot reconstruct the whole invoice.

That limitation matters. The local audit script in this repo does not access Anthropic billing, cannot reproduce a vendor bill, and should not be treated as billing telemetry. It inspects local files and ranks visible context surfaces by approximate size. The ground truth for billed tokens is the provider bill. The script is a diagnostic for finding likely contributors after the fact.

The measurement chain is therefore:

```text
provider bill line  ->  389,169 cache-creation input tokens
local file audit    ->  ranked visible surfaces that could explain the load
human review        ->  decide what to shrink, archive, or stop carrying forward
```

That is less dramatic than a neat cost table. It is also the only version I can defend.

---

## What was loaded that I did not see

The visible prompt was small. The surrounding runtime surfaces were not.

The largest obvious surface was the transcript store under `~/.claude/projects/`. A sample taken during the original launch window showed about 817 MB across 24 project directories, with the largest hidden project memory around 254 MB. Not all of that is loaded into every session. The point is that the local runtime had enough historical material nearby that "resume this project" was no longer a cheap operation.

The project instruction tree was another contributor. `CLAUDE.md`, project-specific rules, memory indexes, handoff notes, and governance files were each reasonable in isolation. Over months, they had become a standing context layer. A file that starts as "helpful operating context" can quietly become a default tax if it is treated as always relevant.

Hooks and automation added a different kind of load. Some hooks were useful only when a task needed them, but they still ran around prompt submission, session start, tool use, or shutdown. A hook that emits model-visible text once is easy to ignore. A hook that emits on every prompt becomes a recurring cost, and failed auth loops can make the repetition worse.

The tool surface also mattered. The setup included MCP server configuration, skills, and agent definitions. The launch-window sample counted 2 MCP servers, 35 skills, and 2 agents. Again, the exact token contribution depends on the runtime and what is actually invoked, but those surfaces are part of the context environment around the session.

Finally, the conversation branch itself was the most important conceptual surface. Git said one thing; the model history said another. Being on git `main` did not mean the agent was on a clean reasoning branch.

---

## What I changed

The first change was behavioral: I stopped treating "resume" as the safe default. If the task meaning changes, I start a fresh session and recover from files. I use old branches only when the raw conversation history is explicitly needed.

Second, I moved durable state into durable files. Decisions, handoffs, project status, and next steps belong in small, named artifacts that a fresh session can read on demand. They do not belong only in a swollen transcript.

Third, I tightened the boot path. One internal handoff file had grown to about 351 KB. Rotating it down to about 24 KB cut a worst-case full read by roughly 93%. The archive still exists for search, but it is no longer something a session should read during boot.

Fourth, I audited hooks for whether they were conditional or unconditional. The rule I use now is simple: if a hook emits text into the model window, it needs to justify that emission for the current task. Side-effect-only hooks are different; model-visible hooks are context.

Fifth, I built this audit kit because guessing was not working. I wanted a boring local report that listed the surfaces I controlled: transcript store, instruction files, hooks, skills, MCP config, agents, and generated reports. The result is not a perfect token counter. It is a way to decide where to look first.

---

## How to measure your own

The no-install version is just shell inspection.

```bash
du -sh ~/.claude/projects 2>/dev/null
find . -name CLAUDE.md -type f -not -path '*/node_modules/*' -print0 | xargs -0 wc -c
ls -la ~/.claude/hooks ~/.claude/skills ~/.claude/agents 2>/dev/null
```

Those commands will not tell you what the model actually billed. They will tell you whether your local surfaces are obviously large.

The scripted path is the report generator in this repo:

```bash
git clone https://github.com/skinny-cloud/runtime-diet-autopilot
cd runtime-diet-autopilot
bash scripts/claude-runtime-diet-report.sh /path/to/your/project
```

The report uses byte-based token estimates for ranking. Treat the estimates as a triage tool, not accounting. If `~/.claude/projects` is hundreds of megabytes, or a project instruction file has become a small book, the exact tokenizer is not the first problem. The first problem is deciding whether that material belongs in the next session at all.

---

## What this does not teach

This kit cannot access Anthropic billing. It cannot read the live conversation window. It cannot see runtime responses from MCP servers. It cannot know which large surface is semantically important for your current task. It cannot promise that shrinking one file will lower the next bill.

It also cannot replace judgment. A large instruction file may be exactly what a regulated workflow needs. A long transcript may be necessary for a careful postmortem. The mistake is not having large context. The mistake is carrying it by default without knowing it is there.

---

## Generalization to other agent runtimes

This example is Claude Code specific because that is the environment I was running. The pattern is not Claude specific.

Any agent runtime with file-based standing context can develop the same shape: Cursor rules, Aider config, Continue plugin manifests, Cline memory, MCP server lists, local transcript stores, generated reports, and automation hooks. The names change, but the audit question stays the same:

```text
What can this agent load before I ask the task-specific question?
```

For another runtime, I would start by finding the equivalent of:

- project instructions;
- global instructions;
- transcript or memory stores;
- tool/plugin registries;
- hook or automation outputs;
- generated logs and reports in the project tree.

Then I would rank by size, ask whether each surface is needed for the next task, and move durable state into smaller files that can be read deliberately.

---

## Closing

The 389K line was not caused by one bad file. It was the result of many reasonable context surfaces becoming a default bundle. The fix was not to make the agent know less. It was to stop making every session inherit everything. 
