#!/usr/bin/env bash
# lib/logger.sh - Structured JSONL logging for the bootstrap framework

log_event() {
    local level="$1"
    local phase="$2"
    local message="$3"
    local metadata="${4:-"{}"}"
    local hash="${5:-""}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Construct JSON using jq for safety; fallback to basic printf if jq is missing in the minimal env
    if command -v jq >/dev/null 2>&1; then
        jq -n -c \
            --arg ts "$timestamp" \
            --arg lvl "$level" \
            --arg ph "$phase" \
            --arg msg "$message" \
            --argjson meta "$metadata" \
            --arg h "$hash" \
            '{timestamp: $ts, level: $lvl, phase: $ph, message: $msg, metadata: $meta, hash: $h}'
    else
        # Fallback for environments lacking jq during early bootstrap
        printf '{"timestamp":"%s","level":"%s","phase":"%s","message":"%s","metadata":%s,"hash":"%s"}\n' \
            "$timestamp" "$level" "$phase" "$message" "$metadata" "$hash"
    fi
}

log_info()  { log_event "INFO"  "$1" "$2" "$3" "$4"; }
log_warn()  { log_event "WARN"  "$1" "$2" "$3" "$4"; }
log_error() { log_event "ERROR" "$1" "$2" "$3" "$4"; }
log_state() { log_event "STATE" "$1" "$2" "$3" "$4"; }
log_fatal() { log_event "FATAL" "$1" "$2" "$3" "$4"; exit 1; }
