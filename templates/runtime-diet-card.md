# Runtime Diet Card

Use this after you run the baseline.

Share only redacted values. Do not include client names, private repo names, raw transcript text, API keys, hostnames, usernames, or private paths.

```text
My Claude Runtime Diet Card

Largest visible surface:
[example: ~/.claude/projects - 762MB]

Largest recent session branch:
[example: ~19.8M rough local token-equivalent bytes]

Hooks configured:
[example: 7]

Skills / rules surface:
[example: 40KB]

Top suspect:
[example: long reused session branch / repeated hook output / oversized rules]

Next expensive-session rule:
[example: start fresh unless this task truly needs old branch context]
```

## Why This Exists

The goal is not to flex a scary number. The goal is to make your next session policy visible.

Good share:

```text
I thought my Claude prompt was small. My largest visible runtime surface was ~/.claude/projects at 762MB. New rule: fresh session before Opus unless the old branch is explicitly needed.
```

Bad share:

```text
Here are my private transcript paths and client repo names.
```

