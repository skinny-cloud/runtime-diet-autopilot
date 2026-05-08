#!/usr/bin/env bash
# claude-runtime-diet-report.sh
# One-command report generator for the Claude Code Runtime Diet Autopilot.
# Markdown deliverables to disk; ANSI Runtime Diet Card to stderr (when isatty).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BASELINE_SCRIPT="${SCRIPT_DIR}/claude-runtime-static-baseline.sh"
RULES_FILE="${SCRIPT_DIR}/runtime-diet-rules.jsonl"
PROJECT_DIR="$PWD"
OUT_DIR=""
BASELINE_ARGS=()
COLOR_ENABLED=false
[[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]] && COLOR_ENABLED=true

# Card geometry: 74 chars total. Border is `┃ ` + 70 text + ` ┃`.
CARD_INNER=70

usage() {
  cat <<'USAGE'
Usage: claude-runtime-diet-report.sh [options] [project-dir]

Options:
  --out-dir DIR         Write generated files to DIR.
  --no-redact           Pass through to baseline script.
  --skip-transcripts    Pass through to baseline script.
  --all-transcripts     Pass through to baseline script.
  --transcript-days N   Pass through to baseline script.
  --max-transcripts N   Pass through to baseline script.
  --no-color            Disable ANSI rendering on stderr.
  -h, --help            Show this help.

Output files:
  my-runtime-baseline.md     Raw read-only baseline.
  my-baseline-worksheet.md   Auto-filled top-five worksheet.
  my-runtime-diet-card.md    Share-safe summary card (markdown).
  my-runtime-diet-card.txt   Plain-text card for screenshots.
  my-opus-passport.md        Auto-drafted expensive-session gate.
  NEXT-SESSION-RULE.md       Top three recommended session rules.
  README.md                  Report index.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)            OUT_DIR="${2:-}"; shift 2 ;;
    --no-color)           COLOR_ENABLED=false; BASELINE_ARGS+=("--no-color"); shift ;;
    --no-redact|--skip-transcripts|--all-transcripts)
                          BASELINE_ARGS+=("$1"); shift ;;
    --transcript-days|--max-transcripts)
                          BASELINE_ARGS+=("$1" "${2:-}"); shift 2 ;;
    -h|--help)            usage; exit 0 ;;
    *)                    PROJECT_DIR="$1"; shift ;;
  esac
done

[[ -f "$BASELINE_SCRIPT" ]] || { echo "ERROR: baseline script not found: $BASELINE_SCRIPT" >&2; exit 2; }
[[ -f "$RULES_FILE" ]]     || { echo "ERROR: rules file not found: $RULES_FILE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required for rule scoring. Install jq and re-run." >&2
  exit 2
}

[[ -z "$OUT_DIR" ]] && OUT_DIR="runtime-diet-report-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd -P)"

BASELINE_FILE="${OUT_DIR}/my-runtime-baseline.md"
WORKSHEET_FILE="${OUT_DIR}/my-baseline-worksheet.md"
CARD_MD="${OUT_DIR}/my-runtime-diet-card.md"
CARD_TXT="${OUT_DIR}/my-runtime-diet-card.txt"
PASSPORT_FILE="${OUT_DIR}/my-opus-passport.md"
RULE_FILE="${OUT_DIR}/NEXT-SESSION-RULE.md"
INDEX_FILE="${OUT_DIR}/README.md"

# ---- ANSI ----
if $COLOR_ENABLED; then
  R=$'\e[0m'; B=$'\e[1m'; D=$'\e[2m'
  CY=$'\e[36m'; GR=$'\e[32m'; YL=$'\e[33m'; RD=$'\e[31m'; MG=$'\e[35m'
else
  R=""; B=""; D=""; CY=""; GR=""; YL=""; RD=""; MG=""
fi
say() { $COLOR_ENABLED && printf '%s\n' "$*" >&2 || true; }

# ---- text wrap helper (plain text, fixed width, hard-cut on long tokens) ----
# wrap_text WIDTH "text..."  -> emits one wrapped line per stdout line.
# Splits on whitespace; any single token longer than WIDTH is hard-cut.
wrap_text() {
  local width="$1" text="$2"
  awk -v w="$width" '
    function flush(   line) { if (length(buf)) { print buf; buf="" } }
    {
      n = split($0, words, /[ \t]+/)
      for (k = 1; k <= n; k++) {
        word = words[k]
        if (word == "") continue
        # Hard-cut tokens longer than width.
        while (length(word) > w) {
          if (length(buf) > 0) { print buf; buf="" }
          print substr(word, 1, w)
          word = substr(word, w + 1)
        }
        if (length(buf) == 0) {
          buf = word
        } else if (length(buf) + 1 + length(word) <= w) {
          buf = buf " " word
        } else {
          print buf
          buf = word
        }
      }
    }
    END { flush() }
  ' <<< "$text"
}

# Emit a fully-bordered card line padded to CARD_INNER chars (plain text).
# Usage: card_line "content"
card_line() {
  printf '┃ %-*s ┃\n' "$CARD_INNER" "$1"
}

# Wrap content to CARD_INNER then emit each wrapped line as a card row.
# Usage: card_wrap "long text..."
card_wrap() {
  local line
  while IFS= read -r line; do
    card_line "$line"
  done < <(wrap_text "$CARD_INNER" "$1")
}

# Same for the colorized stderr render. Color codes wrap each plain line so
# the %-Ns padding math (which only sees plain chars) stays correct.
say_card_line() {
  $COLOR_ENABLED || return 0
  printf '%s%s┃%s %s%-*s%s %s%s┃%s\n' \
    "$B" "$MG" "$R" "$2" "$CARD_INNER" "$1" "$R" "$B" "$MG" "$R" >&2
}
say_card_wrap() {
  local color="${2:-}" line
  while IFS= read -r line; do
    say_card_line "$line" "$color"
  done < <(wrap_text "$CARD_INNER" "$1")
}

# ---- run baseline ----
say "${D}[1/4] Generating baseline...${R}"
bash "$BASELINE_SCRIPT" "${BASELINE_ARGS[@]}" "$PROJECT_DIR" > "$BASELINE_FILE"

# ---- extract structured rows from baseline ----
say "${D}[2/4] Extracting top surfaces and hidden memory...${R}"

TOP_TSV="${OUT_DIR}/.top.tsv"
ALL_TSV="${OUT_DIR}/.all.tsv"
MEM_TSV="${OUT_DIR}/.mem.tsv"

awk '
  /^## Top Local Surfaces To Inspect First/ { in_s=1; next }
  in_s && /^## /                            { in_s=0 }
  in_s && /^[[:space:]]*[0-9]/ {
    bytes=$1; approx=$2; size=$3
    $1=""; $2=""; $3=""; sub(/^[ \t]+/, "")
    print bytes "\t" approx "\t" size "\t" $0
  }
' "$BASELINE_FILE" > "$ALL_TSV"
head -n 5 "$ALL_TSV" > "$TOP_TSV"

awk '
  /^## Hidden Claude Project Memory/ { in_s=1; next }
  in_s && /^## /                     { in_s=0 }
  in_s && /^[[:space:]]*[0-9]/ {
    bytes=$1; approx=$2; size=$3; files=$4
    $1=""; $2=""; $3=""; $4=""; sub(/^[ \t]+/, "")
    print bytes "\t" approx "\t" size "\t" files "\t" $0
  }
' "$BASELINE_FILE" > "$MEM_TSV"

GENERATED_AT="$(awk -F': ' '/^- generated_at:/ { print $2; exit }' "$BASELINE_FILE")"
PROJECT_LABEL="$(awk -F': ' '/^- project_dir:/ { print $2; exit }' "$BASELINE_FILE")"
PI_COUNT="$(awk -F': ' '/^- project_instruction_files_found:/ { print $2; exit }' "$BASELINE_FILE")"
PI_COUNT="${PI_COUNT:-0}"

HOOK_COUNT="$(
  awk '/^## Hook Summary/{i=1;next} i&&/^## /{exit} i&&/^- /{c++} END{print c+0}' "$BASELINE_FILE"
)"

# ---- card surface signals ----
LARGEST_SURFACE="$(awk -F '\t' 'NR==1 { print $4 " - " $3; exit }' "$TOP_TSV")"
LARGEST_SURFACE="${LARGEST_SURFACE:-No top surface found}"

LARGEST_BRANCH="$(awk -F '\t' '$4 ~ /<claude-project:|jsonl/ { print $4 " - " $3; exit }' "$ALL_TSV")"
LARGEST_BRANCH="${LARGEST_BRANCH:-No individual recent session branch in top five}"

RULES_SURFACE="$(awk -F '\t' '$4 ~ /rules|skills|CLAUDE\.md|AGENTS\.md|GEMINI\.md|README\.md|\.windsurfrules|\.cursorrules|AI-WORKFLOW\.md/ { print $4 " - " $3; exit }' "$ALL_TSV")"
RULES_SURFACE="${RULES_SURFACE:-No rules/skills/instruction surface found}"

LARGEST_MEMORY="$(awk -F '\t' 'NR==1 { print $5 " - " $3 " (" $4 " files)"; exit }' "$MEM_TSV")"
LARGEST_MEMORY="${LARGEST_MEMORY:-No hidden project memory found}"

MEM_TOTAL_BYTES="$(awk -F '\t' '{ s+=$1 } END { print s+0 }' "$MEM_TSV")"
MEM_TOTAL_HUMAN="$(awk -v b="$MEM_TOTAL_BYTES" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf (i==1?"%d%s":"%.1f%s"),b,u[i]}')"
MEM_PROJECT_COUNT="$(wc -l < "$MEM_TSV" | tr -d ' ')"

TOP_PATH="$(awk -F '\t' 'NR==1 { print $4; exit }' "$TOP_TSV")"

# ---- top-3 rule scoring ----
# Scoring inputs: ranked surface paths from top-5 (rank 1=5pts ... rank 5=1pt).
# Bonuses: +3 if rule matches and HOOK_COUNT>0 (settings rule), +3 if matches
# and PI_COUNT>0 (instructions rule), +2 if rule matches LARGEST_BRANCH path.
# The default rule (id=default, pattern=".*") is excluded from scoring and used
# only as fallback if fewer than 3 non-default rules score >0.
RANK_PATHS=()
while IFS=$'\t' read -r _ _ _ p; do
  [[ -n "$p" ]] && RANK_PATHS+=("$p")
done < "$TOP_TSV"

# Build TSV "score\tid\ttitle\treason\taction" via jq, sort desc, pick top 3.
SCORES_TSV="${OUT_DIR}/.scores.tsv"

# Pass surface paths and bonus signals to jq as a JSON sidecar.
SIGNALS_JSON="$(
  jq -n \
    --argjson ranks "$(printf '%s\n' "${RANK_PATHS[@]}" | jq -R . | jq -s .)" \
    --arg branch "$LARGEST_BRANCH" \
    --argjson hooks "${HOOK_COUNT:-0}" \
    --argjson pi "${PI_COUNT:-0}" \
    '{ranks:$ranks, branch:$branch, hooks:$hooks, pi:$pi}'
)"

jq -r --argjson s "$SIGNALS_JSON" '
  . as $rule
  | select($rule.id != "default")
  | ($rule.pattern) as $pat
  | (
      # rank-weighted match score: rank 1 -> 5 pts, rank 2 -> 4, ...
      reduce range(0; ($s.ranks | length)) as $i (0;
        if ($s.ranks[$i] | test($pat; "i"))
        then . + (5 - $i)
        else .
        end)
    ) as $rank_score
  | (if $rank_score > 0 then 1 else 0 end) as $matched
  | (
      ( if ($matched == 1 and $rule.id == "settings"     and $s.hooks > 0) then 3 else 0 end)
    + ( if ($matched == 1 and $rule.id == "instructions" and $s.pi    > 0) then 3 else 0 end)
    + ( if ($matched == 1 and ($s.branch | test($pat; "i")))               then 2 else 0 end)
    ) as $bonus
  | ($rank_score + $bonus) as $score
  | select($score > 0)
  | [$score, $rule.id, $rule.title, $rule.reason, $rule.action] | @tsv
' "$RULES_FILE" | sort -t $'\t' -k1,1nr -k2,2 > "$SCORES_TSV"

# Pad to 3 with the default rule if needed.
SCORED_COUNT=$(wc -l < "$SCORES_TSV" | tr -d ' ')
if (( SCORED_COUNT < 3 )); then
  jq -r '
    select(.id == "default")
    | [0, .id, .title, .reason, .action] | @tsv
  ' "$RULES_FILE" >> "$SCORES_TSV"
fi

# Read top-3 into parallel arrays.
TOP_IDS=();   TOP_TITLES=(); TOP_REASONS=(); TOP_ACTIONS=()
while IFS=$'\t' read -r _ id title reason action; do
  [[ -z "$id" ]] && continue
  TOP_IDS+=("$id")
  TOP_TITLES+=("$title")
  TOP_REASONS+=("$reason")
  TOP_ACTIONS+=("$action")
  (( ${#TOP_IDS[@]} >= 3 )) && break
done < "$SCORES_TSV"

# Convenience: first rule drives "top suspect" / single-rule legacy fields.
TOP_REASON="${TOP_REASONS[0]:-Visible local surface worth inspecting before the next expensive session.}"
NEXT_RULE_TITLE="${TOP_TITLES[0]:-Inspect this surface}"
NEXT_RULE_ACTION="${TOP_ACTIONS[0]:-Inspect this surface and pick one safe cleanup or isolation rule.}"

# ---- per-row classification for the worksheet (first non-default match) ----
classify_path() {
  local path="$1"
  jq -rs --arg p "$path" '
    ( map(select(.id != "default" and (.pattern as $re | $p | test($re; "i")))) | first ) as $hit
    | if $hit
      then "\($hit.reason)\t\($hit.action)"
      else (map(select(.id == "default")) | first) as $d
        | "\($d.reason)\t\($d.action)"
      end
  ' "$RULES_FILE"
}

md_escape() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# Decode literal "\n" sequences (from jq @tsv) back into real newlines.
decode_action() { printf '%s' "$1" | sed 's/\\n/\n/g'; }

# Single-line action summary for table cells / box rows: real and literal
# newlines collapse to single spaces.
flatten_action() { decode_action "$1" | tr '\n' ' ' | sed 's/  */ /g'; }

# ---- worksheet ----
say "${D}[3/4] Writing worksheet, card, passport, rule, index...${R}"

{
  echo "# Runtime Diet Baseline Worksheet - Auto-Filled"
  echo
  echo "**Generated**: ${GENERATED_AT:-unknown}"
  echo
  echo "**Project**: ${PROJECT_LABEL:-unknown}"
  echo
  echo "Rows auto-filled from \`my-runtime-baseline.md\`. \`approx_tok\` is byte-count ranking, not exact billed tokens."
  echo
  echo "## Top Five Visible Context Surfaces"
  echo
  echo "| Rank | Surface | Evidence | Approx Tok | Why It Matters | Action |"
  echo "|---:|---|---|---:|---|---|"
  rank=1
  while IFS=$'\t' read -r bytes approx size path; do
    [[ -z "$path" ]] && continue
    IFS=$'\t' read -r reason action < <(classify_path "$path")
    echo "| ${rank} | $(md_escape "$path") | ${size}; ${bytes} bytes | ${approx} | $(md_escape "$reason") | $(md_escape "$(flatten_action "$action")") |"
    rank=$((rank + 1))
  done < "$TOP_TSV"
  echo
  echo "## Hidden Claude Project Memory (Top 5)"
  echo
  echo "Per-project session stores under \`~/.claude/projects/\`. Total: **${MEM_TOTAL_HUMAN}** across **${MEM_PROJECT_COUNT}** projects."
  echo
  echo "| Rank | Project Slug | Size | Approx Tok | JSONL Files |"
  echo "|---:|---|---:|---:|---:|"
  rank=1
  while IFS=$'\t' read -r bytes approx size files slug; do
    [[ -z "$slug" ]] && continue
    echo "| ${rank} | $(md_escape "$slug") | ${size} | ${approx} | ${files} |"
    rank=$((rank + 1))
    [[ "$rank" -gt 5 ]] && break
  done < "$MEM_TSV"
  echo
  echo "## Auto Score"
  echo
  echo "| Signal | Result |"
  echo "|---|---:|"
  echo "| Project instruction files found | ${PI_COUNT} |"
  echo "| Hooks configured | ${HOOK_COUNT} |"
  echo "| Top visible surface | $(md_escape "$LARGEST_SURFACE") |"
  echo "| Largest hidden project memory | $(md_escape "$LARGEST_MEMORY") |"
  echo "| Total hidden project memory | ${MEM_TOTAL_HUMAN} across ${MEM_PROJECT_COUNT} projects |"
  echo
  echo "## Recommended Next Expensive-Session Rules (Top 3)"
  echo
  for i in "${!TOP_IDS[@]}"; do
    echo "### ${TOP_TITLES[$i]}"
    echo
    decode_action "${TOP_ACTIONS[$i]}"
    echo
    echo "_Why_: ${TOP_REASONS[$i]}"
    echo
  done
} > "$WORKSHEET_FILE"

# ---- card markdown ----
{
  echo "# My Claude Runtime Diet Card"
  echo
  echo "Generated from a read-only local baseline. Redact project names, client names, hostnames, and private paths before sharing."
  echo
  echo '```text'
  echo "My Claude Runtime Diet Card"
  echo
  echo "Largest visible surface:"
  while IFS= read -r l; do echo "  $l"; done < <(wrap_text $((CARD_INNER - 2)) "$LARGEST_SURFACE")
  echo
  echo "Hidden project memory total:"
  echo "  $MEM_TOTAL_HUMAN across $MEM_PROJECT_COUNT projects"
  echo
  echo "Largest hidden project memory:"
  while IFS= read -r l; do echo "  $l"; done < <(wrap_text $((CARD_INNER - 2)) "$LARGEST_MEMORY")
  echo
  echo "Largest recent session branch:"
  while IFS= read -r l; do echo "  $l"; done < <(wrap_text $((CARD_INNER - 2)) "$LARGEST_BRANCH")
  echo
  echo "Hooks configured: $HOOK_COUNT"
  echo
  echo "Skills / rules surface:"
  while IFS= read -r l; do echo "  $l"; done < <(wrap_text $((CARD_INNER - 2)) "$RULES_SURFACE")
  echo
  echo "Top suspect:"
  while IFS= read -r l; do echo "  $l"; done < <(wrap_text $((CARD_INNER - 2)) "$TOP_REASON")
  echo
  echo "Next expensive-session rules (top 3):"
  for i in "${!TOP_IDS[@]}"; do
    n=$((i + 1))
    echo "  ${n}) ${TOP_TITLES[$i]}"
    while IFS= read -r l; do echo "       $l"; done < <(wrap_text $((CARD_INNER - 7)) "$(flatten_action "${TOP_ACTIONS[$i]}")")
  done
  echo '```'
} > "$CARD_MD"

# ---- card plain text (screenshot-friendly, monospace box, wrapped) ----
{
  printf '┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n'
  card_line "                  My Claude Runtime Diet Card                       "
  printf '┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\n'

  card_line "Largest visible surface"
  card_wrap "  $LARGEST_SURFACE"
  card_line ""

  card_line "Hidden project memory total"
  card_wrap "  $MEM_TOTAL_HUMAN across $MEM_PROJECT_COUNT projects"
  card_line ""

  card_line "Largest hidden project memory"
  card_wrap "  $LARGEST_MEMORY"
  card_line ""

  card_line "Hooks configured: $HOOK_COUNT"
  card_line ""

  card_line "Skills / rules surface"
  card_wrap "  $RULES_SURFACE"
  card_line ""

  card_line "Top suspect"
  card_wrap "  $TOP_REASON"
  card_line ""

  card_line "Next expensive-session rules (top 3)"
  for i in "${!TOP_IDS[@]}"; do
    n=$((i + 1))
    card_wrap "  ${n}) ${TOP_TITLES[$i]}"
    card_wrap "       $(flatten_action "${TOP_ACTIONS[$i]}")"
  done
  printf '┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n'
} > "$CARD_TXT"

# ---- passport ----
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
  echo "[choose only files needed for this task]"
  echo
  echo "Allowed tools / MCP servers:"
  echo "[choose minimum useful tool set]"
  echo
  echo "Old session branch needed?"
  echo "[x] No - start fresh unless this task truly depends on old branch context"
  echo "[ ] Yes - compact first"
  echo
  echo "Top visible runtime risk:"
  echo "  $TOP_REASON"
  echo
  echo "Cleanup actions before starting:"
  for i in "${!TOP_IDS[@]}"; do
    n=$((i + 1))
    echo "  ${n}) ${TOP_TITLES[$i]} - $(flatten_action "${TOP_ACTIONS[$i]}")"
  done
  echo
  echo "Preservation instruction if compacting:"
  echo "  Preserve only objective, current files, unresolved blockers, tests run, next exact command."
  echo
  echo "Stop rule:"
  echo "  If the task changes, /clear or start fresh instead of carrying this branch forward."
  echo '```'
} > "$PASSPORT_FILE"

# ---- next session rule (top 3) ----
{
  echo "# Next Session Rules"
  echo
  for i in "${!TOP_IDS[@]}"; do
    n=$((i + 1))
    echo "## Rule ${n}: ${TOP_TITLES[$i]}"
    echo
    decode_action "${TOP_ACTIONS[$i]}"
    echo
    echo "Why: ${TOP_REASONS[$i]}"
    echo
  done
} > "$RULE_FILE"

# ---- index ----
{
  echo "# Runtime Diet Report"
  echo
  echo "**Project**: ${PROJECT_LABEL:-unknown}"
  echo
  echo "**Generated**: ${GENERATED_AT:-unknown}"
  echo
  echo "Open in order:"
  echo
  echo "1. \`my-runtime-diet-card.md\` (or \`.txt\` for screenshots)"
  echo "2. \`NEXT-SESSION-RULE.md\`"
  echo "3. \`my-baseline-worksheet.md\`"
  echo "4. \`my-runtime-baseline.md\`"
  echo
  echo "Generated files are a starting point. Review before sharing."
  echo
  echo "This kit does not access Anthropic billing and does not guarantee lower usage."
  echo "It ranks visible local surfaces you control."
} > "$INDEX_FILE"

rm -f "$TOP_TSV" "$ALL_TSV" "$MEM_TSV" "$SCORES_TSV"

# ---- terminal card render to stderr ----
say ""
say "${B}${MG}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${R}"
say_card_line "                  ${B}My Claude Runtime Diet Card${R}                       " ""
say "${B}${MG}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${R}"

say_card_line "${CY}Largest visible surface${R}" ""
say_card_wrap "  $LARGEST_SURFACE" "$YL"
say_card_line "" ""

say_card_line "${CY}Hidden project memory total${R}     ${RD}${B}biggest invisible cost${R}" ""
say_card_wrap "  ${MEM_TOTAL_HUMAN} across ${MEM_PROJECT_COUNT} projects" "$RD$B"
say_card_line "" ""

say_card_line "${CY}Largest hidden project memory${R}" ""
say_card_wrap "  $LARGEST_MEMORY" "$YL"
say_card_line "" ""

say_card_line "${CY}Hooks configured${R}: ${B}${HOOK_COUNT}${R}" ""
say_card_line "" ""

say_card_line "${CY}Top suspect${R}" ""
say_card_wrap "  $TOP_REASON" "$D"
say_card_line "" ""

say_card_line "${CY}Next expensive-session rules (top 3)${R}" ""
for i in "${!TOP_IDS[@]}"; do
  n=$((i + 1))
  say_card_wrap "  ${n}) ${TOP_TITLES[$i]}" "$GR$B"
  say_card_wrap "       $(flatten_action "${TOP_ACTIONS[$i]}")" "$D"
done
say "${B}${MG}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${R}"
say ""
say "${D}[4/4] Done.${R}"
say ""

cat <<DONE
Runtime Diet Report written to:
  $OUT_DIR

Open first:
  $CARD_MD
  $RULE_FILE

Plain-text card for screenshots:
  $CARD_TXT

Raw baseline:
  $BASELINE_FILE
DONE
