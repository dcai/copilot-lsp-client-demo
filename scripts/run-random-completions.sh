#!/usr/bin/env bash
set -euo pipefail

export PATH="${PATH:-/usr/bin:/bin}:$HOME/.bun/bin:/opt/homebrew/bin"

count="${1:-50}"

if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
    echo "Usage: $0 [positive-run-count]"
    exit 1
fi

pick_fixture() {
    local roll
    roll=$((RANDOM % 100))

    if [[ "$roll" -lt 80 ]]; then
        echo "fixtures/sample.ts:8:2"
        return
    fi

    if [[ "$roll" -lt 90 ]]; then
        echo "fixtures/sample.md:5:2"
        return
    fi

    if [[ "$roll" -lt 95 ]]; then
        echo "fixtures/sample.sh:6:0"
        return
    fi

    echo "fixtures/sample.yaml:4:13"
}

date
for run in $(seq 1 "$count"); do
    selected="$(pick_fixture)"
    IFS=':' read -r file line character <<<"$selected"

    echo "===== RUN $run / $count ====="
    echo "fixture=$file line=$line character=$character"

    bun run complete --file "$file" --line "$line" --character "$character" --accept-rate 60
    echo
done
