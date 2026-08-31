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
TARGET_LINES="${TARGET_LINES:-100}"
PROMPT_MIN_LINES="${PROMPT_MIN_LINES:-$((TARGET_LINES + 20))}"
WORK_DIR="$(mktemp -d)"
# Keep Copilot's session state, installed plugins, MCP configuration, and logs
# isolated to this run. cleanup removes the entire directory when the run ends.
COPILOT_HOME="$WORK_DIR/copilot-home"
export COPILOT_HOME

mkdir -p "$OUTPUT_DIR" "$COPILOT_HOME"

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
log_debug "copilot_home=$COPILOT_HOME (disposable)"
log_debug "pwd=$(pwd)"
log_debug "user=$(whoami)"
log_debug "home=${HOME:-}"
log_debug "shell=${SHELL:-}"
log_debug "path=${PATH:-}"
log_debug "tty=$(tty 2>/dev/null || echo 'no-tty')"

configure_auth() {
    if [ -n "${COPILOT_GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
        log_debug "using authentication token supplied by the environment"
        return
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_debug "GitHub CLI is unavailable and no Copilot authentication token was supplied"
        echo "Copilot needs COPILOT_GITHUB_TOKEN, GH_TOKEN, or GITHUB_TOKEN. Alternatively, authenticate the GitHub CLI with: gh auth login" >&2
        exit 1
    fi

    COPILOT_GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"

    if [ -z "$COPILOT_GITHUB_TOKEN" ]; then
        log_debug "GitHub CLI has no usable authentication token"
        echo "Copilot needs a token. Run: gh auth login" >&2
        exit 1
    fi

    export COPILOT_GITHUB_TOKEN
    log_debug "using authentication token from GitHub CLI"
}

pick_format() {
    local roll
    roll=$(((RANDOM % 100) + 1))

    if [ "$roll" -le 50 ]; then
        echo "typescript:ts"
        return
    fi

    if [ "$roll" -le 65 ]; then
        echo "javascript:js"
        return
    fi

    if [ "$roll" -le 70 ]; then
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

    if [ "$roll" -le 90 ]; then
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

COMMON_REQUIREMENTS="$(
    cat <<EOF
- Write at least $PROMPT_MIN_LINES lines
- Create or overwrite only that file
- Work from scratch in the current empty directory
- Do not inspect or rely on any existing repository files
- Do not print the file contents to stdout
- After creating the first draft, review the saved file and remove every non-content line, including blank lines, comment lines, separators, and explanatory text
- After writing the file, print only one short confirmation line with the path and total line count
EOF
)"

COMMON_RULES="$(
    cat <<EOF
- Safe content only
- The final saved file must not contain blank lines or comments
- No explanation
- Use this randomness seed: $SEED
EOF
)"

build_prompt() {
    local file_label
    local format_rules

    case "$FORMAT" in
        typescript)
            file_label="TypeScript"
            format_rules="$(
                cat <<EOF
- Every remaining line must be valid-looking TypeScript code
- Prefer functions, types, interfaces, constants, imports, utility helpers, and realistic snippets
- No markdown fences
- No intro or outro
EOF
            )"
            ;;
        javascript)
            file_label="JavaScript"
            format_rules="$(
                cat <<EOF
- Every remaining line must be valid-looking JavaScript code
- Prefer functions, objects, arrays, utilities, logs, and realistic snippets
- No intro or outro
EOF
            )"
            ;;
        python)
            file_label="Python"
            format_rules="$(
                cat <<EOF
- Every remaining line must be valid-looking Python code
- Prefer functions, dictionaries, lists, utility helpers, small classes, error handling, and realistic snippets
- No intro or outro
EOF
            )"
            ;;
        markdown)
            file_label="Markdown"
            format_rules="$(
                cat <<EOF
- Every remaining line must be meaningful Markdown content
- Use headings, bullets, checklists, code-indented examples, quotes, and short notes
- No fenced code blocks
- No intro or outro outside the markdown itself
EOF
            )"
            ;;
        lua)
            file_label="Lua"
            format_rules="$(
                cat <<EOF
- Every remaining line must be valid-looking Lua code
- Prefer local functions, tables, modules, utility helpers, conditionals, loops, and realistic snippets
- No intro or outro
EOF
            )"
            ;;
        json)
            file_label="JSON"
            format_rules="$(
                cat <<EOF
- Every remaining line must belong to realistic JSON content
- The content should look like realistic JSON fragments or a large JSON structure spread across lines
- Use objects, arrays, nested fields, strings, booleans, and numbers
- No intro or outro
EOF
            )"
            ;;
        yaml)
            file_label="YAML"
            format_rules="$(
                cat <<EOF
- Every remaining line must belong to realistic YAML content
- The content should look like realistic YAML documents or config fragments
- Use nested keys, lists, strings, booleans, and numbers
- No intro or outro
EOF
            )"
            ;;
        *)
            echo "Unknown format: $FORMAT" >&2
            exit 1
            ;;
    esac

    cat <<EOF
Write $file_label directly to this file: $OUTPUT_FILE

Requirements:
$COMMON_REQUIREMENTS

Rules:
$format_rules
$COMMON_RULES
EOF
}

PROMPT="$(build_prompt)"
configure_auth

log_debug "prompt preview start"
printf '%s\n' "$PROMPT" | sed -n '1,20p' | tee -a "$DEBUG_LOG"
log_debug "prompt preview end"
cd "$WORK_DIR"
log_debug "copilot_cwd=$(pwd)"
log_debug "running copilot command..."

set +e
"$COPILOT_BIN" \
    -C "$WORK_DIR" \
    --disable-builtin-mcps \
    --no-custom-instructions \
    --no-remote \
    --no-remote-export \
    --yolo \
    --model gpt-5.6-luna \
    -p "$PROMPT" \
    --silent >>"$DEBUG_LOG" 2>&1
COPILOT_EXIT_CODE="$?"
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
echo "## > tree"
# this filters the tree to confirm the new file is in the tree
tree -P "$(basename "$OUTPUT_FILE")" "$OUTPUT_DIR"
echo
echo "## > head"
head -n 10 "$OUTPUT_FILE"
echo
echo "## > tail"
tail -n 10 "$OUTPUT_FILE"
