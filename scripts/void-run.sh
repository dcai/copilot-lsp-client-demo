#!/usr/bin/env bash
set -euo pipefail

export SHELL="/bin/bash"
export LOGNAME="$USER"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export TMPDIR="${TMPDIR:-/tmp}"

REPO_DIR="$HOME/iag/copilot-lsp-stats"
COPILOT_BIN="$HOME/.local/bin/copilot"
OUTPUT_DIR="$REPO_DIR/void"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
DEBUG_LOG="$OUTPUT_DIR/void-run-debug.log"
TARGET_LINES="${TARGET_LINES:-300}"
PROMPT_MIN_LINES="${PROMPT_MIN_LINES:-$((TARGET_LINES + 20))}"
WORK_DIR="$(mktemp -d)"

mkdir -p "$OUTPUT_DIR"

log_debug() {
    local message
    message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$DEBUG_LOG"
}

cleanup() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT

log_debug "starting void-run.sh"
log_debug "repo_dir=$REPO_DIR"
log_debug "copilot_bin=$COPILOT_BIN"
log_debug "output_dir=$OUTPUT_DIR"
log_debug "timestamp=$TIMESTAMP"
log_debug "target_lines=$TARGET_LINES"
log_debug "prompt_min_lines=$PROMPT_MIN_LINES"
log_debug "work_dir=$WORK_DIR"
log_debug "pwd=$(pwd)"
log_debug "user=$(whoami)"
log_debug "home=${HOME:-}"
log_debug "shell=${SHELL:-}"
log_debug "path=${PATH:-}"
log_debug "tty=$(tty 2>/dev/null || echo 'no-tty')"

pick_format() {
    local roll
    roll=$(((RANDOM % 100) + 1))

    if [ "$roll" -le 45 ]; then
        echo "typescript:ts"
        return
    fi

    if [ "$roll" -le 55 ]; then
        echo "javascript:js"
        return
    fi

    if [ "$roll" -le 65 ]; then
        echo "python:py"
        return
    fi

    if [ "$roll" -le 75 ]; then
        echo "markdown:md"
        return
    fi

    if [ "$roll" -le 85 ]; then
        echo "lua:lua"
        return
    fi

    if [ "$roll" -le 93 ]; then
        echo "json:json"
        return
    fi

    echo "yaml:yaml"
}

FORMAT_AND_EXT="$(pick_format)"
FORMAT="${FORMAT_AND_EXT%%:*}"
EXT="${FORMAT_AND_EXT##*:}"
OUTPUT_FILE="$OUTPUT_DIR/$TIMESTAMP.$FORMAT.$EXT"
SEED="$(date +%s)"

log_debug "selected format=$FORMAT ext=$EXT seed=$SEED"
log_debug "output_file=$OUTPUT_FILE"

build_prompt() {
    case "$FORMAT" in
        typescript)
            cat <<EOF
Write TypeScript directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- Every line must be valid-looking TypeScript or TypeScript-style comments
- Prefer functions, types, interfaces, constants, imports, utility helpers, and realistic snippets
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        javascript)
            cat <<EOF
Write JavaScript directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- Every line must be valid-looking JavaScript or JavaScript-style comments
- Prefer functions, objects, arrays, utilities, logs, and realistic snippets
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        python)
            cat <<EOF
Write Python directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- Every line must be valid-looking Python or Python-style comments
- Prefer functions, dictionaries, lists, utility helpers, small classes, error handling, and realistic snippets
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        markdown)
            cat <<EOF
Write Markdown directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- Use headings, bullets, checklists, code-indented examples, quotes, and short notes
- Safe content only
- No fenced code blocks
- No intro or outro outside the markdown itself
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        lua)
            cat <<EOF
Write Lua directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- Every line must be valid-looking Lua or Lua-style comments
- Prefer local functions, tables, modules, utility helpers, conditionals, loops, and realistic snippets
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        json)
            cat <<EOF
Write JSON directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- The content should look like realistic JSON fragments or a large JSON structure spread across lines
- Use objects, arrays, nested fields, strings, booleans, and numbers
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        yaml)
            cat <<EOF
Write YAML directly to this file: $OUTPUT_FILE

Requirements:
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After writing the file, print only one short confirmation line with the path and total line count

Rules:
- The content should look like realistic YAML documents or config fragments
- Use nested keys, lists, strings, booleans, numbers, and comments
- Safe content only
- No markdown fences
- No intro or outro
- No explanation
- Use this randomness seed: $SEED
EOF
            ;;
        *)
            echo "Unknown format: $FORMAT" >&2
            exit 1
            ;;
    esac
}

PROMPT="$(build_prompt)"

log_debug "prompt preview start"
printf '%s\n' "$PROMPT" | sed -n '1,20p' | tee -a "$DEBUG_LOG"
log_debug "prompt preview end"
cd "$WORK_DIR"
log_debug "copilot_cwd=$(pwd)"
log_debug "running copilot command"

TIMEOUT_BIN=""
# if command -v timeout >/dev/null 2>&1; then
#     TIMEOUT_BIN="timeout"
# fi
# if command -v gtimeout >/dev/null 2>&1; then
#     TIMEOUT_BIN="gtimeout"
# fi
# if [ -n "$TIMEOUT_BIN" ]; then
#     log_debug "using timeout_bin=$TIMEOUT_BIN duration=300s"
# else
#     log_debug "no timeout binary found; copilot may hang indefinitely"
# fi

set +e
if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" 300 \
        "$COPILOT_BIN" \
        -C "$WORK_DIR" \
        --disable-builtin-mcps \
        --experimental \
        --no-custom-instructions \
        --yolo \
        --model gpt-5-mini \
        -p "$PROMPT" \
        --silent >>"$DEBUG_LOG" 2>&1
    COPILOT_EXIT_CODE="$?"
else
    "$COPILOT_BIN" \
        -C "$WORK_DIR" \
        --disable-builtin-mcps \
        --experimental \
        --no-custom-instructions \
        --yolo \
        --model gpt-5-mini \
        -p "$PROMPT" \
        --silent >>"$DEBUG_LOG" 2>&1
    COPILOT_EXIT_CODE="$?"
fi
set -e

log_debug "copilot_exit_code=$COPILOT_EXIT_CODE"

if [ "$COPILOT_EXIT_CODE" -ne 0 ]; then
    log_debug "copilot command failed"
    exit "$COPILOT_EXIT_CODE"
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    log_debug "copilot completed without creating output file"
    echo "Expected Copilot to write $OUTPUT_FILE, but the file was not created." >&2
    exit 1
fi

ACTUAL_LINES="$(awk 'END { print NR }' "$OUTPUT_FILE")"
log_debug "actual_lines=$ACTUAL_LINES"

if [ "$ACTUAL_LINES" -lt "$TARGET_LINES" ]; then
    log_debug "output file has fewer lines than requested"
    echo "Expected at least $TARGET_LINES lines in $OUTPUT_FILE, got $ACTUAL_LINES." >&2
    exit 1
fi

log_debug "void-run.sh completed successfully"
echo "Wrote $ACTUAL_LINES lines to:"
echo "$OUTPUT_FILE"
echo "Work dir:"
echo "$WORK_DIR"
echo
echo "Tree:"
# this filters the tree to confirm the new file is in the tree
tree -P "$(basename "$OUTPUT_FILE")" "$OUTPUT_DIR"
echo
echo "Head:"
head -n 10 "$OUTPUT_FILE"
echo
echo "Tail:"
tail -n 10 "$OUTPUT_FILE"
