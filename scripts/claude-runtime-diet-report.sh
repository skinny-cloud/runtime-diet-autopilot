#!/usr/bin/env bash
# claude-runtime-diet-report.sh
# One-command report generator for the Claude Code Runtime Diet Autopilot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BASELINE_SCRIPT="${SCRIPT_DIR}/claude-runtime-static-baseline.sh"
PROJECT_DIR="$PWD"
OUT_DIR=""
BASELINE_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  claude-runtime-diet-report.sh [options] [project-dir]

Options:
  --out-dir DIR           Write generated files to DIR.
  --no-redact             Pass through to baseline script.
  --skip-transcripts      Pass through to baseline script.
  --all-transcripts       Pass through to baseline script.
  --transcript-days N     Pass through to baseline script.
  --max-transcripts N     Pass through to baseline script.
  -h, --help              Show this help.

Output:
  my-runtime-baseline.md       Raw read-only baseline.
  my-baseline-worksheet.md     Auto-filled top-five worksheet.
  my-runtime-diet-card.md      Auto-filled share-safe summary card.
  my-opus-passport.md          Auto-drafted expensive-session gate.
  NEXT-SESSION-RULE.md         One recommended session rule.
  README.md                    Report index.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --no-redact|--skip-transcripts|--all-transcripts)
      BASELINE_ARGS+=("$1")
      shift
      ;;
    --transcript-days|--max-transcripts)
      BASELINE_ARGS+=("$1" "${2:-}")
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

if [[ ! -x "$BASELINE_SCRIPT" && ! -f "$BASELINE_SCRIPT" ]]; then
  echo "ERROR: baseline script not found: $BASELINE_SCRIPT" >&2
  exit 2
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="runtime-diet-report-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd -P)"

BASELINE_FILE="${OUT_DIR}/my-runtime-baseline.md"
WORKSHEET_FILE="${OUT_DIR}/my-baseline-worksheet.md"
CARD_FILE="${OUT_DIR}/my-runtime-diet-card.md"
PASSPORT_FILE="${OUT_DIR}/my-opus-passport.md"
RULE_FILE="${OUT_DIR}/NEXT-SESSION-RULE.md"
INDEX_FILE="${OUT_DIR}/README.md"
TOP_ROWS_TSV="${OUT_DIR}/.top-rows.tsv"
ALL_ROWS_TSV="${OUT_DIR}/.all-rows.tsv"

bash "$BASELINE_SCRIPT" "${BASELINE_ARGS[@]}" "$PROJECT_DIR" > "$BASELINE_FILE"

awk '
  /^## Top Local Surfaces To Inspect First/ { in_section = 1; next }
  in_section && /^## / { exit }
  in_section && /^[[:space:]]*[0-9]/ {
    bytes = $1
    approx = $2
    size = $3
    $1 = ""
    $2 = ""
    $3 = ""
    sub(/^[ \t]+/, "")
    sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]+[0-9][0-9]:[0-9][0-9][ \t]+/, "")
    print bytes "\t" approx "\t" size "\t" $0
  }
' "$BASELINE_FILE" | head -n 5 > "$TOP_ROWS_TSV"

awk '
  /^[[:space:]]*[0-9]/ {
    bytes = $1
    approx = $2
    size = $3
    $1 = ""
    $2 = ""
    $3 = ""
    sub(/^[ \t]+/, "")
    sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ \t]+[0-9][0-9]:[0-9][0-9][ \t]+/, "")
    print bytes "\t" approx "\t" size "\t" $0
  }
' "$BASELINE_FILE" | sort -t "$(printf '\t')" -k1,1nr > "$ALL_ROWS_TSV"

project_dir="$(awk -F': ' '/^- project_dir:/ { print $2; exit }' "$BASELINE_FILE")"
generated_at="$(awk -F': ' '/^- generated_at:/ { print $2; exit }' "$BASELINE_FILE")"
instruction_count="$(awk -F': ' '/^- project_instruction_files_found:/ { print $2; exit }' "$BASELINE_FILE")"
instruction_count="${instruction_count:-unknown}"

md_escape() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

reason_for_path() {
  local path="$1"
  case "$path" in
    *"<claude-project:"*|*"jsonl"*|*"~/.claude/projects"*)
      printf 'Large transcript/session surface; long-lived branches can make the next session heavier than the prompt looks.'
      ;;
    *"CLAUDE.md"*|*"AGENTS.md"*|*"GEMINI.md"*|*"README.md"*|*".windsurfrules"*|*".cursorrules"*|*"AI-WORKFLOW.md"*)
      printf 'Project instruction surface; may be read directly or used as standing context for agent behavior.'
      ;;
    *"~/.claude/rules"*|*"/.claude/rules"*)
      printf 'Global rules surface; can affect many sessions even when the current project looks small.'
      ;;
    *"settings.json"*|*"~/.claude.json"*)
      printf 'Tool, MCP, and hook configuration surface; may activate extra context or model-visible hook output.'
      ;;
    *"skills"*)
      printf 'Skill/procedure surface; useful, but oversized procedures should not become invisible context tax.'
      ;;
    *)
      printf 'Visible local surface worth inspecting before the next expensive session.'
      ;;
  esac
}

action_for_path() {
  local path="$1"
  case "$path" in
    *"<claude-project:"*|*"jsonl"*|*"~/.claude/projects"*)
      printf 'Start fresh for unrelated work; compact only with explicit carry-forward instructions.'
      ;;
    *"CLAUDE.md"*|*"AGENTS.md"*|*"GEMINI.md"*|*"README.md"*|*".windsurfrules"*|*".cursorrules"*|*"AI-WORKFLOW.md"*)
      printf 'Trim repeated instructions; move long procedures into referenced docs or skills.'
      ;;
    *"~/.claude/rules"*|*"/.claude/rules"*)
      printf 'Keep only cross-project rules globally; move project-specific rules into the project.'
      ;;
    *"settings.json"*|*"~/.claude.json"*)
      printf 'Review hooks/MCP defaults; disable noisy or irrelevant tools for this project.'
      ;;
    *"skills"*)
      printf 'Keep skills focused and callable; avoid loading long procedures as standing prose.'
      ;;
    *)
      printf 'Inspect this surface and pick one safe cleanup or isolation rule.'
      ;;
  esac
}

hook_count="$(
  awk '
    /^## Hook Summary/ { in_hooks = 1; next }
    in_hooks && /^## / { exit }
    in_hooks && /^- / { count++ }
    END { print count + 0 }
  ' "$BASELINE_FILE"
)"

largest_surface="$(
  awk -F '\t' 'NR == 1 { print $4 " - " $3; exit }' "$TOP_ROWS_TSV"
)"
largest_surface="${largest_surface:-No top surface found}"

largest_branch="$(
  awk -F '\t' '$4 ~ /<claude-project:|jsonl/ { print $4 " - " $3; exit }' "$ALL_ROWS_TSV"
)"
largest_branch="${largest_branch:-No individual recent session branch in top five}"

rules_surface="$(
  awk -F '\t' '$4 ~ /rules|skills|CLAUDE.md|AGENTS.md|GEMINI.md|README.md|.windsurfrules|.cursorrules|AI-WORKFLOW.md/ { print $4 " - " $3; exit }' "$ALL_ROWS_TSV"
)"
rules_surface="${rules_surface:-No rules/skills/instruction surface found}"

top_path="$(awk -F '\t' 'NR == 1 { print $4; exit }' "$TOP_ROWS_TSV")"
top_suspect="$(reason_for_path "$top_path")"
next_rule="$(action_for_path "$top_path")"

{
  echo "# Runtime Diet Baseline Worksheet - Auto-Filled"
  echo
  echo "**Generated**: ${generated_at:-unknown}"
  echo
  echo "**Project**: ${project_dir:-unknown}"
  echo
  echo "The rows below are auto-filled from \`my-runtime-baseline.md\`. The \`approx_tok\` value is a rough byte-count ranking signal, not exact billed tokens."
  echo
  echo "## Top Five Visible Context Surfaces"
  echo
  echo "| Rank | Surface | Evidence From Baseline | Approx Tok | Why It Might Matter | Action |"
  echo "|---:|---|---|---:|---|---|"

  rank=1
  while IFS=$'\t' read -r bytes approx size path; do
    reason="$(reason_for_path "$path")"
    action="$(action_for_path "$path")"
    echo "| ${rank} | $(md_escape "$path") | ${size}; ${bytes} bytes | ${approx} | $(md_escape "$reason") | $(md_escape "$action") |"
    rank=$((rank + 1))
  done < "$TOP_ROWS_TSV"

  echo
  echo "## Auto Score"
  echo
  echo "| Signal | Result |"
  echo "|---|---:|"
  echo "| Project instruction files found | ${instruction_count} |"
  echo "| Hooks configured | ${hook_count} |"
  echo "| Top visible surface | $(md_escape "$largest_surface") |"
  echo
  echo "## Recommended Next Expensive-Session Rule"
  echo
  echo "\`\`\`text"
  echo "$next_rule"
  echo "\`\`\`"
} > "$WORKSHEET_FILE"

{
  echo "# My Claude Runtime Diet Card"
  echo
  echo "Generated from a read-only local baseline. Redact project names, client names, hostnames, usernames, private paths, and raw transcript details before sharing."
  echo
  echo '```text'
  echo "My Claude Runtime Diet Card"
  echo
  echo "Largest visible surface:"
  echo "$largest_surface"
  echo
  echo "Largest recent session branch:"
  echo "$largest_branch"
  echo
  echo "Hooks configured:"
  echo "${hook_count}"
  echo
  echo "Skills / rules surface:"
  echo "$rules_surface"
  echo
  echo "Top suspect:"
  echo "$top_suspect"
  echo
  echo "Next expensive-session rule:"
  echo "$next_rule"
  echo '```'
} > "$CARD_FILE"

{
  echo "# Opus Passport - Auto Draft"
  echo
  echo "Use this before an expensive Claude Code session."
  echo
  echo '```text'
  echo "Opus Passport"
  echo
  echo "Task objective:"
  echo "[state the one task this session is allowed to solve]"
  echo
  echo "Allowed context files:"
  echo "[choose only the files needed for this task]"
  echo
  echo "Allowed tools / MCP servers:"
  echo "[choose the minimum useful tool set]"
  echo
  echo "Old session branch needed?"
  echo "[x] No - start fresh unless the current task truly depends on old branch context"
  echo "[ ] Yes - compact first"
  echo
  echo "Top visible runtime risk:"
  echo "$top_suspect"
  echo
  echo "Cleanup action before starting:"
  echo "$next_rule"
  echo
  echo "Preservation instruction if compacting:"
  echo "Preserve only the objective, current files, unresolved blockers, tests run, and next exact command."
  echo
  echo "Stop rule:"
  echo "If the task changes, I will clear or start fresh instead of carrying this branch forward."
  echo '```'
} > "$PASSPORT_FILE"

{
  echo "# Next Session Rule"
  echo
  echo "$next_rule"
  echo
  echo "Why:"
  echo
  echo "$top_suspect"
} > "$RULE_FILE"

{
  echo "# Runtime Diet Report"
  echo
  echo "**Project**: ${project_dir:-unknown}"
  echo
  echo "**Generated**: ${generated_at:-unknown}"
  echo
  echo "Open these in order:"
  echo
  echo "1. \`my-runtime-diet-card.md\`"
  echo "2. \`NEXT-SESSION-RULE.md\`"
  echo "3. \`my-baseline-worksheet.md\`"
  echo "4. \`my-runtime-baseline.md\`"
  echo
  echo "The generated files are a starting point. Review before sharing publicly."
  echo
  echo "This kit does not access Anthropic billing and does not guarantee lower usage. It ranks visible local surfaces you control."
} > "$INDEX_FILE"

rm -f "$TOP_ROWS_TSV" "$ALL_ROWS_TSV"

cat <<DONE
Runtime Diet Report written to:
  $OUT_DIR

Open first:
  $CARD_FILE
  $RULE_FILE

Raw baseline:
  $BASELINE_FILE
DONE
