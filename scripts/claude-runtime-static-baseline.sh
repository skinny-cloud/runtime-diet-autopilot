#!/usr/bin/env bash
# claude-runtime-static-baseline.sh
# Read-only inventory of visible Claude Code context surfaces.
# Stdout: markdown report. Stderr: optional ANSI rendering when isatty.

set -euo pipefail

HOME_DIR="${HOME}"
PROJECT_DIR="$PWD"
REDACT=true
SKIP_TRANSCRIPTS=false
SCAN_ALL_TRANSCRIPTS=false
TRANSCRIPT_DAYS=45
MAX_TRANSCRIPTS=20
COLOR_ENABLED=false
[[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]] && COLOR_ENABLED=true

usage() {
  cat <<'USAGE'
Usage: claude-runtime-static-baseline.sh [options] [project-dir]

Options:
  --no-redact          Print raw paths, hostname, hook command bodies.
  --skip-transcripts   Do not scan transcript files.
  --all-transcripts    Scan all transcripts instead of recent only.
  --transcript-days N  Recent transcript window. Default: 45.
  --max-transcripts N  Number of transcript rows to show. Default: 20.
  --no-color           Disable ANSI rendering on stderr.
  -h, --help           Show this help.

Default redacts paths, hostname, and hook command bodies. approx_tok is byte_count/4
for ranking only; it is not Anthropic billing telemetry.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-redact)         REDACT=false; shift ;;
    --skip-transcripts)  SKIP_TRANSCRIPTS=true; shift ;;
    --all-transcripts)   SCAN_ALL_TRANSCRIPTS=true; shift ;;
    --transcript-days)   TRANSCRIPT_DAYS="${2:-}"; shift 2 ;;
    --max-transcripts)   MAX_TRANSCRIPTS="${2:-}"; shift 2 ;;
    --no-color)          COLOR_ENABLED=false; shift ;;
    -h|--help)           usage; exit 0 ;;
    *)                   PROJECT_DIR="$1"; shift ;;
  esac
done

[[ "$TRANSCRIPT_DAYS" =~ ^[0-9]+$ ]] || { echo "ERROR: --transcript-days must be a positive integer." >&2; exit 2; }
[[ "$MAX_TRANSCRIPTS" =~ ^[0-9]+$ ]] || { echo "ERROR: --max-transcripts must be a positive integer." >&2; exit 2; }

# ---- ANSI ----
if $COLOR_ENABLED; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_MAGENTA=$'\e[35m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_MAGENTA=""
fi

ansi() { $COLOR_ENABLED && printf '%s' "$*" >&2 || true; }
banner() { ansi "${C_CYAN}${C_BOLD}━━━ $1 ━━━${C_RESET}\n"; }

# ---- path normalize ----
normalize_input_path() {
  local raw="$1"
  if [[ "$raw" =~ ^[A-Za-z]:[\\/].* ]]; then
    if command -v cygpath >/dev/null 2>&1; then cygpath -u "$raw"; return 0; fi
    local d; d="$(printf '%s' "${raw:0:1}" | tr '[:upper:]' '[:lower:]')"
    local rest="${raw:2}"; rest="${rest//\\//}"
    [[ -d "/mnt/${d}" ]] && printf '/mnt/%s%s' "$d" "$rest" || printf '/%s%s' "$d" "$rest"
    return 0
  fi
  printf '%s' "$raw"
}

PROJECT_DIR="$(normalize_input_path "$PROJECT_DIR")"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)" || { echo "ERROR: project dir not found: $PROJECT_DIR" >&2; exit 2; }

# ---- size primitives ----
byte_count() {
  local p="$1"
  if [[ -f "$p" ]]; then wc -c < "$p" 2>/dev/null | tr -d ' '
  elif [[ -d "$p" ]]; then du -sk "$p" 2>/dev/null | awk '{print $1*1024}'
  else printf '0'; fi
}

approx_tokens() { printf '%d' $((($1 + 3) / 4)); }

human_size() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$b" 2>/dev/null || printf '%sB' "$b"
  else
    awk -v b="$b" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf (i==1?"%d%s":"%.1f%s"),b,u[i]}'
  fi
}

shorten_home() {
  local p="$1"
  [[ "$p" == "$HOME_DIR" ]] && { printf '~'; return; }
  [[ "$p" == "${HOME_DIR}/"* ]] && { printf '~/%s' "${p#${HOME_DIR}/}"; return; }
  printf '%s' "$p"
}

project_hash() {
  command -v sha256sum >/dev/null 2>&1 \
    && printf '%s' "$1" | sha256sum | awk '{print substr($1,1,10)}' \
    || printf 'redacted'
}

display_path() {
  local p="$1"
  if ! $REDACT; then shorten_home "$p"; return; fi
  case "$p" in
    "$PROJECT_DIR")     printf '<project-root>' ;;
    "$PROJECT_DIR"/*)   printf '<project-root>/%s' "${p#${PROJECT_DIR}/}" ;;
    "${HOME_DIR}/.claude/projects/"*|"${HOME_DIR}/.config/claude/projects/"*)
      local rel="$p"
      rel="${rel#${HOME_DIR}/.claude/projects/}"
      rel="${rel#${HOME_DIR}/.config/claude/projects/}"
      local proj="${rel%%/*}" file; file="$(basename "$p")"
      [[ "$rel" == */subagents/* ]] \
        && printf '<claude-project:%s>/subagents/%s' "$(project_hash "$proj")" "$file" \
        || printf '<claude-project:%s>/%s' "$(project_hash "$proj")" "$file"
      ;;
    *) shorten_home "$p" ;;
  esac
}

redact_text() {
  sed -e "s#${HOME_DIR}#~#g" -E \
      -e 's/(Bearer )[[:alnum:]._%+\/=-]+/\1<redacted>/g' \
      -e 's/((API_KEY|api_key|TOKEN|token|SECRET|secret|PASSWORD|password)[^ =:]*[=:])[^[:space:]]+/\1<redacted>/g'
}

render_hook_line() {
  local line="$1"
  if $REDACT && [[ "$line" == *" :: "* ]]; then
    local prefix="${line%% :: *}" cmd="${line#* :: }"
    printf '%s :: <command:%s redacted>\n' "$prefix" "$(project_hash "$cmd")"
  else
    printf '%s\n' "$line" | redact_text
  fi
}

# ---- table writer (single source of truth) ----
SIZE_HEADER_FMT='%12s %12s %12s %s\n'

write_size_header() { printf "$SIZE_HEADER_FMT" "bytes" "approx_tok" "size" "path"; printf "$SIZE_HEADER_FMT" "-----" "----------" "----" "----"; }

# stdin: list of paths, one per line. stdout: header + rows in input order.
print_sizes() {
  write_size_header
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    local b; b="$(byte_count "$p")"
    printf "$SIZE_HEADER_FMT" "$b" "$(approx_tokens "$b")" "$(human_size "$b")" "$(display_path "$p")"
  done
}

# stdin: list of paths. stdout: TSV rows for piping into render_sorted.
emit_sortable() {
  while IFS= read -r p; do
    [[ -e "$p" ]] || continue
    local b; b="$(byte_count "$p")"
    printf '%s\t%s\t%s\t%s\n' "$b" "$(approx_tokens "$b")" "$(human_size "$b")" "$(display_path "$p")"
  done
}

# stdin: TSV. stdout: header + top-N sorted by bytes desc.
render_sorted() {
  local limit="$1"
  write_size_header
  sort -t "$(printf '\t')" -k1,1nr | head -n "$limit" \
    | awk -F '\t' -v fmt="$SIZE_HEADER_FMT" '{ printf fmt, $1, $2, $3, $4 }'
}

# ---- transcripts ----
file_mtime() {
  if stat -c '%y' "$1" >/dev/null 2>&1; then
    stat -c '%y' "$1" | awk '{print $1 "\t" substr($2,1,5)}'
  elif stat -f '%Sm' -t '%Y-%m-%d	%H:%M' "$1" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%d	%H:%M' "$1"
  else printf 'unknown\tunknown'; fi
}

transcript_candidates() {
  local r
  for r in "${HOME_DIR}/.claude/projects" "${HOME_DIR}/.config/claude/projects"; do
    [[ -d "$r" ]] || continue
    if $SCAN_ALL_TRANSCRIPTS; then
      find "$r" -type f \( -name "*.jsonl" -o -name "*.json" \) -print 2>/dev/null
    else
      find "$r" -type f \( -name "*.jsonl" -o -name "*.json" \) -mtime "-${TRANSCRIPT_DAYS}" -print 2>/dev/null
    fi
  done
}

format_transcripts() {
  write_size_header
  while IFS= read -r p; do
    [[ -f "$p" ]] || continue
    local b; b="$(byte_count "$p")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$b" "$(approx_tokens "$b")" "$(human_size "$b")" "$(file_mtime "$p")" "$(display_path "$p")"
  done | sort -t "$(printf '\t')" -k1,1nr | head -n "$MAX_TRANSCRIPTS" \
    | awk -F '\t' '{ printf "%12s %12s %12s %s %s %s\n", $1, $2, $3, $4, $5, $6 }'
}

# ---- candidates ----
project_instruction_candidates() {
  {
    local rel
    for rel in CLAUDE.md AGENTS.md GEMINI.md README.md AI-WORKFLOW.md \
               .windsurfrules .cursorrules .claude/CLAUDE.md .codex/AGENTS.md \
               .github/copilot-instructions.md; do
      [[ -f "${PROJECT_DIR}/${rel}" ]] && printf '%s\n' "${PROJECT_DIR}/${rel}"
    done
    find "$PROJECT_DIR" -maxdepth 4 \
      \( -path "*/.git" -o -path "*/node_modules" -o -path "*/vendor" -o -path "*/.venv" -o -path "*/dist" -o -path "*/build" \) -prune -o \
      \( -name "CLAUDE.md" -o -name "AGENTS.md" -o -name "GEMINI.md" -o -name "README.md" \
         -o -name "AI-WORKFLOW.md" -o -name "*-WORKFLOW.md" -o -name ".windsurfrules" -o -name ".cursorrules" \
         -o -name "*.instructions.md" -o -name "*.mdc" -o -name "copilot-instructions.md" \
      \) -type f -print 2>/dev/null
  } | sort -u
}

project_claude_dirs() {
  find "$PROJECT_DIR" -maxdepth 3 \
    \( -path "*/.git" -o -path "*/node_modules" -o -path "*/vendor" -o -path "*/.venv" -o -path "*/dist" -o -path "*/build" \) -prune -o \
    \( -path "*/.claude" -o -path "*/.codex" \) -type d -print 2>/dev/null | sort
}

# Hidden claude project memory store: rank top-level dirs under ~/.claude/projects/
hidden_project_memory() {
  local root="${HOME_DIR}/.claude/projects"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null
}

top_surface_candidates() {
  project_instruction_candidates
  project_claude_dirs
  printf '%s\n' "${HOME_DIR}/.claude/CLAUDE.md" \
                "${HOME_DIR}/.claude/settings.json" \
                "${HOME_DIR}/.claude/rules" \
                "${HOME_DIR}/.claude/skills" \
                "${HOME_DIR}/.claude/memory" \
                "${HOME_DIR}/.claude/projects"
  find "${HOME_DIR}/.claude/skills" -name "SKILL.md" -type f -print 2>/dev/null || true
  hidden_project_memory
  $SKIP_TRANSCRIPTS || transcript_candidates
}

h() { printf '\n## %s\n\n' "$1"; banner "$1"; }

# ---- header ----
GENERATED_AT="$(date -Iseconds)"
echo "# Claude Runtime Static Baseline"
echo
echo "- generated_at: ${GENERATED_AT}"
echo "- project_dir: $(display_path "$PROJECT_DIR")"
$REDACT && echo "- host: <host:redacted>" || echo "- host: $(hostname 2>/dev/null || echo unknown)"
echo "- approx_token_estimate: byte_count / 4 for ranking only; not billing telemetry"
echo "- transcript_scan: $($SKIP_TRANSCRIPTS && printf 'skipped' || { $SCAN_ALL_TRANSCRIPTS && printf 'all' || printf 'last_%s_days' "$TRANSCRIPT_DAYS"; })"

ansi "${C_BOLD}${C_MAGENTA}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_RESET}\n"
ansi "${C_BOLD}${C_MAGENTA}┃${C_RESET}  ${C_BOLD}Claude Code Runtime Diet — Static Baseline${C_RESET}                ${C_BOLD}${C_MAGENTA}┃${C_RESET}\n"
ansi "${C_BOLD}${C_MAGENTA}┃${C_RESET}  ${C_DIM}project: $(display_path "$PROJECT_DIR")${C_RESET}\n"
ansi "${C_BOLD}${C_MAGENTA}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_RESET}\n\n"

PI_COUNT="$(project_instruction_candidates | wc -l | tr -d ' ')"

h "Project Scan Check"
echo "- project_dir_exists: yes"
echo "- project_instruction_files_found: ${PI_COUNT}"
[[ "$PI_COUNT" == "0" ]] && echo "- warning: no project instruction files found. Check the project path."

h "Top Local Surfaces To Inspect First"
top_surface_candidates | emit_sortable | render_sorted 10 || true

h "Hidden Claude Project Memory"
echo "Per-project Claude session stores under \`~/.claude/projects/\`. Most users never see these. They are the biggest invisible cost on long-lived machines."
echo
if [[ -d "${HOME_DIR}/.claude/projects" ]]; then
  printf '%12s %12s %12s %8s  %s\n' "bytes" "approx_tok" "size" "files" "project_slug"
  printf '%12s %12s %12s %8s  %s\n' "-----" "----------" "----" "-----" "------------"
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    bytes="$(byte_count "$d")"
    files="$(find "$d" -type f -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
    slug="$(basename "$d")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$bytes" "$(approx_tokens "$bytes")" "$(human_size "$bytes")" "$files" "$slug"
  done < <(hidden_project_memory) \
    | sort -t "$(printf '\t')" -k1,1nr \
    | awk -F '\t' '{ printf "%12s %12s %12s %8s  %s\n", $1, $2, $3, $4, $5 }'
else
  echo "_No \`~/.claude/projects/\` directory found._"
fi

h "Project Instruction Files"
project_instruction_candidates | print_sizes

h "Project Claude Directories"
project_claude_dirs | print_sizes

h "User Claude Files"
echo "Note: ~/.claude.json may contain sensitive configuration; this script prints byte size only."
echo
printf '%s\n' "${HOME_DIR}/.claude/CLAUDE.md" "${HOME_DIR}/.claude/settings.json" "${HOME_DIR}/.claude.json" | print_sizes

h "User Claude Directories"
printf '%s\n' "${HOME_DIR}/.claude/rules" "${HOME_DIR}/.claude/skills" "${HOME_DIR}/.claude/memory" "${HOME_DIR}/.claude/projects" | print_sizes

h "Largest Project Skill Files"
find "$PROJECT_DIR" -path "*/.claude/skills/*/SKILL.md" -type f -print 2>/dev/null | emit_sortable | render_sorted 20 || true

h "Largest User Skill Files"
find "${HOME_DIR}/.claude/skills" -name "SKILL.md" -type f -print 2>/dev/null | emit_sortable | render_sorted 20 || true

h "Hook Summary"
if command -v jq >/dev/null 2>&1; then
  for s in "$PROJECT_DIR/.claude/settings.json" "$HOME_DIR/.claude/settings.json"; do
    [[ -f "$s" ]] || continue
    echo "### $(display_path "$s")"
    $REDACT && { echo "Note: hook command bodies redacted by default."; echo; }
    jq -r '
      (.hooks // {}) | to_entries[]
      | .key as $event | .value[]
      | (.matcher // "*") as $m
      | (.hooks // [])[]
      | "- \($event) [\($m)] timeout=\(.timeout // "default") :: \(.command)"
    ' "$s" 2>/dev/null | while IFS= read -r line; do render_hook_line "$line"; done || true
    echo
  done
else
  echo "jq not found; skipping structured hook parsing."
fi

h "Transcript Store"
printf '%s\n' "${HOME_DIR}/.claude/projects" "${HOME_DIR}/.config/claude/projects" | print_sizes

h "Largest Recent Transcript Files"
if $SKIP_TRANSCRIPTS; then
  echo "Transcript scan skipped by --skip-transcripts."
elif $SCAN_ALL_TRANSCRIPTS; then
  echo "Scanning all transcript files. Can be slow on long-running machines."
  transcript_candidates | format_transcripts || true
else
  echo "Scanning transcripts modified in the last ${TRANSCRIPT_DAYS} days. Use --all-transcripts for full scan."
  transcript_candidates | format_transcripts || true
fi

h "Next Step"
cat <<'NEXT'
Start with "Top Local Surfaces To Inspect First" and "Hidden Claude Project Memory."
Copy only the rows that explain your next expensive session into the worksheet.

Look first for:
- large always-loaded instruction files
- large skill/rules directories
- large per-project memory stores under ~/.claude/projects/
- hooks that emit model-visible text
- long sessions resumed across unrelated work

Common leak points are redacted by default; run with --no-redact only for private review.
The approx_tok column ranks surfaces locally; it is not exact model context or billing.
NEXT
