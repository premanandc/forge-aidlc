#!/usr/bin/env bash
# metrics.sh append <json>   : append one run record to metrics/runs.jsonl
# metrics.sh summary         : baseline vs harnessed, side by side
#
# A run record is one JSON object. Fields used by summary:
#   ticket, mode (baseline|harnessed), startedAt, wallSeconds, sessions, model,
#   gate.tier1 (pass|fail), gate.tier1FirstPass (true|false), gate.tier2 (pass|fail|skipped),
#   diff.files, diff.insertions, diff.deletions, review.disposition, review.findings,
#   mutationScorePercent, notes
# Compatible with bash 3.2; needs jq.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd); cd "$ROOT"
FILE=metrics/runs.jsonl
case "${1:-}" in
  append)
    [ -n "${2:-}" ] || { echo "usage: bin/metrics.sh append '<json>'" >&2; exit 2; }
    echo "$2" | jq -c . >/dev/null || { echo "metrics: not valid JSON" >&2; exit 2; }
    mkdir -p metrics; echo "$2" | jq -c . >>"$FILE"; echo "metrics: recorded $(echo "$2" | jq -r '"\(.ticket) \(.mode)"')"
    ;;
  summary)
    [ -f "$FILE" ] || { echo "metrics: no runs recorded yet"; exit 0; }
    echo "Speed read beside quality. Every row is one run of a ticket; baseline runs had no chain and no gates until the end."
    echo
    echo "wall = clock time end to end; api = time the model was actually working (sum of session API durations); the gap is waiting: rate-limit backoff, hooks, builds."
    echo
    printf '%-8s %-10s %-8s %-8s %-8s %-7s %-10s %-7s %-14s %-12s %-8s %s\n' ticket mode wall api sessions tier1 first-pass tier2 diff review mutation model
    jq -r '[.ticket, .mode, ((.wallSeconds // 0) | tostring) + "s", (if .apiSeconds then ((.apiSeconds|tostring) + "s") else "-" end), (.sessions // 1 | tostring), (.gate.tier1 // "-"), ((.gate.tier1FirstPass // "-") | tostring), (.gate.tier2 // "-"), ((.diff.files // 0 | tostring) + "f +" + (.diff.insertions // 0 | tostring) + " -" + (.diff.deletions // 0 | tostring)), ((.review.disposition // "-") + "/" + ((.review.findings // 0) | tostring)), ((.mutationScorePercent // "-") | tostring), (.model // "-")] | @tsv' "$FILE" \
      | while IFS=$'\t' read -r t m w a s t1 fp t2 d r mu mo; do printf '%-8s %-10s %-8s %-8s %-8s %-7s %-10s %-7s %-14s %-12s %-8s %s\n' "$t" "$m" "$w" "$a" "$s" "$t1" "$fp" "$t2" "$d" "$r" "$mu" "$mo"; done
    echo
    jq -r 'select(.notes != null) | "  \(.ticket) \(.mode): \(.notes)"' "$FILE"
    ;;
  *) echo "usage: bin/metrics.sh append '<json>' | summary" >&2; exit 2;;
esac
