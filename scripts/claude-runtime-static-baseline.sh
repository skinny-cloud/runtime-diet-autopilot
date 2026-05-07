#!/usr/bin/env bash
# claude-runtime-static-baseline.sh
# Read-only inventory of visible Claude Code context surfaces.

set -euo pipefail

HOME_DIR="${HOME}"
PROJECT_DIR="$PWD"
REDACT_TRANSCRIPTS=true
SKIP_TRANSCRIPTS=false
SCAN_ALL_TRANSCRIPTS=false
TRANSCRIPT_DAYS=45
MAX_TRANSCRIPTS=20

usage() {
  cat <<'USAGE'
Usage:
  claude-runtime-static-baseline.sh [options] [project-dir]

Options:
  --no-redact             Print raw local paths, hostname, transcript project path segments, and hook command bodies.
  --skip-transcripts      Do not scan transcript files.
  --all-transcripts       Scan all transcript files instead of recent files only.
  --transcript-days N     Recent transcript window. Default: 45.
  --max-transcripts N     Number of large transcript files to show. Default: 20.
  -h, --help              Show this help.

Default behavior redacts project paths, hostname, Claude transcript project path
segments, and hook command bodies because they often contain private client,
project, or token-bearing command details. Use --no-redact only for private local
review.

Approximate token counts are rough byte_count / 4 estimates for ranking local text
surfaces. They are not Anthropic billing telemetry and not exact model context usage.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-redact)
      REDACT_TRANSCRIPTS=false
      shift
      ;;
    --skip-transcripts)
      SKIP_TRANSCRIPTS=true
      shift
      ;;
    --all-transcripts)
      SCAN_ALL_TRANSCRIPTS=true
      shift
      ;;
    --transcript-days)
      TRANSCRIPT_DAYS="${2:-}"
      shift 2
      ;;
    --max-transcripts)
      MAX_TRANSCRIPTS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PROJECT_DIR="$1"
      shift
      ;;
  esac
done

if ! [[ "$TRANSCRIPT_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --transcript-days must be a positive integer." >&2
  exit 2
fi

if ! [[ "$MAX_TRANSCRIPTS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-transcripts must be a positive integer." >&2
  exit 2
fi

normalize_input_path() {
  local raw="$1"

  if [[ "$raw" =~ ^[A-Za-z]:[\\/].* ]]; then
    local drive="${raw:0:1}"
    local drive_lower
    drive_lower="$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')"

    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u "$raw"
      return 0
    fi

    local rest="${raw:2}"
    rest="${rest//\\//}"

    if [[ -d "/mnt/${drive_lower}" ]]; then
      printf '/mnt/%s%s' "$drive_lower" "$rest"
    else
      printf '/%s%s' "$drive_lower" "$rest"
    fi
    return 0
  fi

  printf '%s' "$raw"
}

PROJECT_DIR="$(normalize_input_path "$PROJECT_DIR")"
if ! PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"; then
  echo "ERROR: project directory not found: $PROJECT_DIR" >&2
  echo "Try a POSIX-style path, for example /c/__GitHub/my-project or /mnt/c/__GitHub/my-project." >&2
  exit 2
fi

human_header() {
  printf '\n## %s\n\n' "$1"
}

byte_count() {
  local path="$1"
  if [[ -f "$path" ]]; then
    wc -c < "$path" 2>/dev/null | tr -d ' '
  elif [[ -d "$path" ]]; then
    du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}'
  else
    printf '0'
  fi
}

approx_tokens() {
  local bytes="${1:-0}"
  printf '%d' $(((bytes + 3) / 4))
}

human_size() {
  local bytes="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || printf '%sB' "$bytes"
  else
    awk -v b="$bytes" 'BEGIN {
      split("B KiB MiB GiB TiB", u, " ");
      i=1;
      while (b >= 1024 && i < 5) { b = b / 1024; i++ }
      if (i == 1) printf "%d%s", b, u[i]; else printf "%.1f%s", b, u[i]
    }'
  fi
}

shorten_home_path() {
  local path="$1"
  if [[ "$path" == "$HOME_DIR" ]]; then
    printf '~'
  elif [[ "$path" == "${HOME_DIR}/"* ]]; then
    printf '~/%s' "${path#${HOME_DIR}/}"
  else
    printf '%s' "$path"
  fi
}

redact_sensitive_text() {
  sed \
    -e "s#${HOME_DIR}#~#g" \
    -E \
    -e 's/(Bearer )[[:alnum:]._%+\/=-]+/\1<redacted>/g' \
    -e 's/((API_KEY|api_key|TOKEN|token|SECRET|secret|PASSWORD|password)[^ =:]*[=:])[^[:space:]]+/\1<redacted>/g'
}

print_size_header() {
  printf '%12s %12s %12s %s\n' "bytes" "approx_tok" "size" "path"
  printf '%12s %12s %12s %s\n' "-----" "----------" "----" "----"
}

print_size_row() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  local bytes
  bytes="$(byte_count "$path")"
  printf '%12s %12s %12s %s\n' "$bytes" "$(approx_tokens "$bytes")" "$(human_size "$bytes")" "$(display_path "$path")"
}

print_sizes() {
  print_size_header
  while IFS= read -r path; do
    print_size_row "$path"
  done
}

print_sortable_size_rows() {
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    local bytes
    bytes="$(byte_count "$path")"
    printf '%s\t%s\t%s\t%s\n' "$bytes" "$(approx_tokens "$bytes")" "$(human_size "$bytes")" "$(display_path "$path")"
  done
}

render_sorted_size_rows() {
  local limit="$1"
  print_size_header
  sort -t "$(printf '\t')" -k1,1nr \
    | head -n "$limit" \
    | awk -F '\t' '{ printf "%12s %12s %12s %s\n", $1, $2, $3, $4 }'
}

project_hash() {
  local label="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$label" | sha256sum | awk '{print substr($1, 1, 10)}'
  else
    printf 'redacted'
  fi
}

redact_transcript_path() {
  local path="$1"

  if [[ "$REDACT_TRANSCRIPTS" == "true" ]]; then
    local rel="$path"
    rel="${rel#${HOME_DIR}/.claude/projects/}"
    rel="${rel#${HOME_DIR}/.config/claude/projects/}"
    local project="${rel%%/*}"
    local file
    file="$(basename "$path")"
    local hash
    hash="$(project_hash "$project")"

    if [[ "$rel" == */subagents/* ]]; then
      printf '<claude-project:%s>/subagents/%s' "$hash" "$file"
    else
      printf '<claude-project:%s>/%s' "$hash" "$file"
    fi
  else
    printf '%s' "$path"
  fi
}

display_path() {
  local path="$1"

  if [[ "$REDACT_TRANSCRIPTS" != "true" ]]; then
    shorten_home_path "$path"
    return
  fi

  case "$path" in
    "$PROJECT_DIR")
      printf '<project-root>'
      ;;
    "$PROJECT_DIR"/*)
      printf '<project-root>/%s' "${path#${PROJECT_DIR}/}"
      ;;
    "${HOME_DIR}/.claude/projects/"*|"${HOME_DIR}/.config/claude/projects/"*)
      redact_transcript_path "$path"
      ;;
    *)
      shorten_home_path "$path"
      ;;
  esac
}

render_hook_line() {
  local line="$1"

  if [[ "$REDACT_TRANSCRIPTS" == "true" && "$line" == *" :: "* ]]; then
    local prefix command hash
    prefix="${line%% :: *}"
    command="${line#* :: }"
    hash="$(project_hash "$command")"
    printf '%s :: <command:%s redacted; run --no-redact to inspect>\n' "$prefix" "$hash"
    return
  fi

  printf '%s\n' "$line" | redact_sensitive_text
}

file_mtime() {
  local path="$1"
  if stat -c '%y' "$path" >/dev/null 2>&1; then
    stat -c '%y' "$path" | awk '{print $1 "\t" substr($2, 1, 5)}'
  elif stat -f '%Sm' -t '%Y-%m-%d	%H:%M' "$path" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%d	%H:%M' "$path"
  else
    printf 'unknown\tunknown'
  fi
}

transcript_candidates() {
  local root
  for root in "${HOME_DIR}/.claude/projects" "${HOME_DIR}/.config/claude/projects"; do
    [[ -d "$root" ]] || continue

    if [[ "$SCAN_ALL_TRANSCRIPTS" == "true" ]]; then
      find "$root" -type f \( -name "*.jsonl" -o -name "*.json" \) -print 2>/dev/null
    else
      find "$root" -type f \( -name "*.jsonl" -o -name "*.json" \) -mtime "-${TRANSCRIPT_DAYS}" -print 2>/dev/null
    fi
  done
}

format_transcript_listing() {
  print_size_header
  while IFS= read -r path; do
    [[ -f "$path" ]] || continue
    local bytes
    bytes="$(byte_count "$path")"
    local stamp
    stamp="$(file_mtime "$path")"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$bytes" \
      "$(approx_tokens "$bytes")" \
      "$(human_size "$bytes")" \
      "$stamp" \
      "$(redact_transcript_path "$path")"
  done \
    | sort -t "$(printf '\t')" -k1,1nr \
    | head -n "$MAX_TRANSCRIPTS" \
	    | awk -F '\t' '{ printf "%12s %12s %12s %s %s %s\n", $1, $2, $3, $4, $5, $6 }'
}

project_instruction_candidates() {
  {
    for rel in \
      "CLAUDE.md" \
      "AGENTS.md" \
      "GEMINI.md" \
      "README.md" \
      "AI-WORKFLOW.md" \
      ".windsurfrules" \
      ".cursorrules" \
      ".claude/CLAUDE.md" \
      ".codex/AGENTS.md" \
      ".github/copilot-instructions.md"; do
      [[ -f "${PROJECT_DIR}/${rel}" ]] && printf '%s\n' "${PROJECT_DIR}/${rel}"
    done

    find "$PROJECT_DIR" -maxdepth 4 \
      \( -path "*/.git" -o -path "*/node_modules" -o -path "*/vendor" -o -path "*/.venv" -o -path "*/dist" -o -path "*/build" \) -prune -o \
      \( \
        -name "CLAUDE.md" -o \
        -name "AGENTS.md" -o \
        -name "GEMINI.md" -o \
        -name "README.md" -o \
        -name "AI-WORKFLOW.md" -o \
        -name "*-WORKFLOW.md" -o \
        -name ".windsurfrules" -o \
        -name ".cursorrules" -o \
        -name "*.instructions.md" -o \
        -name "*.mdc" -o \
        -name "copilot-instructions.md" \
      \) -type f -print 2>/dev/null
  } | sort -u
}

top_surface_candidates() {
  project_instruction_candidates

  find "$PROJECT_DIR" -maxdepth 3 \
    \( -path "*/.git" -o -path "*/node_modules" -o -path "*/vendor" -o -path "*/.venv" -o -path "*/dist" -o -path "*/build" \) -prune -o \
    \( -path "*/.claude" -o -path "*/.codex" \) \
    -type d -print 2>/dev/null

  printf '%s\n' "${HOME_DIR}/.claude/CLAUDE.md"
  printf '%s\n' "${HOME_DIR}/.claude/settings.json"
  printf '%s\n' "${HOME_DIR}/.claude/rules"
  printf '%s\n' "${HOME_DIR}/.claude/skills"
  printf '%s\n' "${HOME_DIR}/.claude/memory"
  printf '%s\n' "${HOME_DIR}/.claude/projects"

  find "${HOME_DIR}/.claude/skills" -name "SKILL.md" -type f -print 2>/dev/null || true

  if [[ "$SKIP_TRANSCRIPTS" != "true" ]]; then
    transcript_candidates
  fi
}

echo "# Claude Runtime Static Baseline"
echo
echo "- generated_at: $(date -Iseconds)"
echo "- project_dir: $(display_path "$PROJECT_DIR")"
if [[ "$REDACT_TRANSCRIPTS" == "true" ]]; then
  echo "- host: <host:redacted>"
else
  echo "- host: $(hostname 2>/dev/null || echo unknown)"
fi
echo "- approx_token_estimate: byte_count / 4 for ranking only; not billing telemetry"
echo "- transcript_scan: $([[ "$SKIP_TRANSCRIPTS" == "true" ]] && printf 'skipped' || { [[ "$SCAN_ALL_TRANSCRIPTS" == "true" ]] && printf 'all' || printf 'last_%s_days' "$TRANSCRIPT_DAYS"; })"

PROJECT_INSTRUCTION_COUNT="$(project_instruction_candidates | wc -l | tr -d ' ')"

human_header "Project Scan Check"
echo "- project_dir_exists: yes"
echo "- project_instruction_files_found: ${PROJECT_INSTRUCTION_COUNT}"
if [[ "${PROJECT_INSTRUCTION_COUNT}" == "0" ]]; then
  echo "- warning: no project instruction files were found. If you expected CLAUDE.md, AGENTS.md, README.md, .windsurfrules, or similar files, check the project path you passed to the script."
fi

human_header "Top Local Surfaces To Inspect First"
top_surface_candidates | print_sortable_size_rows | render_sorted_size_rows 10 || true

human_header "Project Instruction Files"
project_instruction_candidates | print_sizes

human_header "Project Claude Directories"
find "$PROJECT_DIR" -maxdepth 3 \
  \( -path "*/.git" -o -path "*/node_modules" -o -path "*/vendor" -o -path "*/.venv" -o -path "*/dist" -o -path "*/build" \) -prune -o \
  \( -path "*/.claude" -o -path "*/.codex" \) \
  -type d -print 2>/dev/null | sort | print_sizes

human_header "User Claude Files"
echo "Note: ~/.claude.json may contain sensitive configuration; this script prints byte size only."
echo
{
  printf '%s\n' "${HOME_DIR}/.claude/CLAUDE.md"
  printf '%s\n' "${HOME_DIR}/.claude/settings.json"
  printf '%s\n' "${HOME_DIR}/.claude.json"
} | print_sizes

human_header "User Claude Directories"
{
  printf '%s\n' "${HOME_DIR}/.claude/rules"
  printf '%s\n' "${HOME_DIR}/.claude/skills"
  printf '%s\n' "${HOME_DIR}/.claude/memory"
  printf '%s\n' "${HOME_DIR}/.claude/projects"
} | print_sizes

human_header "Largest Project Skill Files"
find "$PROJECT_DIR" -path "*/.claude/skills/*/SKILL.md" -type f -print 2>/dev/null \
  | print_sortable_size_rows \
  | render_sorted_size_rows 20 || true

human_header "Largest User Skill Files"
find "${HOME_DIR}/.claude/skills" -name "SKILL.md" -type f -print 2>/dev/null \
  | print_sortable_size_rows \
  | render_sorted_size_rows 20 || true

human_header "Hook Summary"
if command -v jq >/dev/null 2>&1; then
	  for settings in "$PROJECT_DIR/.claude/settings.json" "$HOME_DIR/.claude/settings.json"; do
	    [[ -f "$settings" ]] || continue
	    echo "### $(display_path "$settings")"
	    if [[ "$REDACT_TRANSCRIPTS" == "true" ]]; then
	      echo "Note: hook command bodies are redacted by default because commands can contain private paths or tokens."
	      echo
	    fi
	    jq -r '
	      (.hooks // {})
	      | to_entries[]
      | .key as $event
      | .value[]
      | (.matcher // "*") as $matcher
      | (.hooks // [])[]
	      | "- \($event) [\($matcher)] timeout=\(.timeout // "default") :: \(.command)"
	    ' "$settings" 2>/dev/null | while IFS= read -r line; do render_hook_line "$line"; done || true
	    echo
	  done
else
  echo "jq not found; skipping structured hook parsing."
fi

human_header "Transcript Store"
{
  printf '%s\n' "${HOME_DIR}/.claude/projects"
  printf '%s\n' "${HOME_DIR}/.config/claude/projects"
} | print_sizes

human_header "Largest Recent Transcript Files"
if [[ "$SKIP_TRANSCRIPTS" == "true" ]]; then
  echo "Transcript scan skipped by --skip-transcripts."
elif [[ "$SCAN_ALL_TRANSCRIPTS" == "true" ]]; then
  echo "Scanning all transcript files. This can be slow on long-running Claude Code machines."
  transcript_candidates | format_transcript_listing || true
else
  echo "Scanning transcript files modified in the last ${TRANSCRIPT_DAYS} days. Use --all-transcripts for a full scan."
  transcript_candidates | format_transcript_listing || true
fi

human_header "Next Step"
cat <<'NEXT'
Start with "Top Local Surfaces To Inspect First." Copy only the rows that explain
your next expensive session into worksheets/baseline-worksheet.md.

Look first for:
- large always-loaded instruction files;
- large skill/rules directories;
- large transcript stores;
- hooks that emit model-visible text;
- long sessions resumed across unrelated work.

Before sharing this output, scrub hostnames, usernames, project names, client names,
and any path segments you do not want public. Common leak points are redacted
by default; run with --no-redact only for private local review.

The approx_tok column is a rough local byte-count estimate. It helps rank surfaces;
it is not exact model context and not account billing telemetry.

Done. Output is read-only and local.
NEXT
