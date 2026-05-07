# Case Study: The 389K Startup Burn

This case study is sanitized from an internal Runtime Diet audit of a long-running agent harness.

---

## What Happened

A long-running Chief-of-Staff Claude session was restarted after authentication problems.

The user prompt was tiny:

```text
Welcome back.
```

But the first successful expensive-model response created a prompt cache with:

```text
389,169 cache-creation input tokens
```

The visible prompt was not the real cost driver. The active conversation branch carried days of accumulated context.

---

## What The Audit Found

Visible contributing surfaces included:

- multi-day conversation ancestry;
- repeated loop/skill prompt bodies;
- failed authentication messages;
- hook outputs;
- tool and attachment records;
- long-lived automation state.

The largest visible contributor was repeated loop skill injection inside a reused branch, not the fresh user prompt.

---

## Lesson

Git branch and Claude session branch are different things.

You can be on git `main` while Claude is effectively operating on a multi-day conversation branch.

For expensive sessions:

- start clean when work changes;
- preserve continuity in files;
- avoid repeated automation injection while auth/runtime is unhealthy;
- audit visible context surfaces before optimizing randomly.

---

## What This Kit Teaches

This kit does not expose every hidden token source. No local script can do that perfectly.

It teaches the practical move:

> Stop guessing. Inventory the visible surfaces you control, then remove the biggest unnecessary burden before the next expensive session.
