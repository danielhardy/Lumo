#!/bin/zsh
set -euo pipefail

# LUMO-123: opt-in hardware capture of a simultaneous batch export + editing session.
# Drives the shipping editor/scheduler/export stack against real CAMetalDrawables and records
# LiveEditTelemetry editor latency/frame gap, export throughput, and resident-memory delta.
# Requires a logged-in macOS display (a real drawable); never run in CI.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_path="${1:-$repo_root/realworldtest/DSC07826.ARW}"
capture_id="${LUMO_CAPTURE_ID:-LUMO-123}"
item_count="${LUMO_CONCURRENT_CAPTURE_ITEMS:-6}"
gesture_count="${LUMO_CONCURRENT_CAPTURE_GESTURES:-10}"
time_limit="${LUMO_CAPTURE_TIME_LIMIT:-600s}"
output_dir="${LUMO_CAPTURE_OUTPUT_DIR:-/tmp/lumo-123-capture}"
swift_path="$(command -v swift)"
xctest_path="$(xcrun --find xctest 2>/dev/null || true)"

if [[ "$source_path" != /* ]]; then
    source_path="$PWD/$source_path"
fi
cd "$repo_root"

if [[ ! -f "$source_path" ]]; then
    print -u2 "RAW source does not exist: $source_path"
    exit 2
fi
if [[ -z "$swift_path" || ! -x "$swift_path" ]]; then
    print -u2 "Swift executable could not be resolved"
    exit 2
fi
if [[ -z "$xctest_path" || ! -x "$xctest_path" ]]; then
    print -u2 "xctest executable could not be resolved"
    exit 2
fi

secondary="$repo_root/realworldtest/DSC07241.ARW"
secondary_env=()
if [[ -f "$secondary" ]]; then
    secondary_env=(--env "LUMO_CONCURRENT_CAPTURE_RAW_SECONDARY=$secondary")
fi

mkdir -p "$output_dir"
source_stem="${source_path:t:r}"
stamp="$(date +%Y%m%d-%H%M%S)"
trace_path="$output_dir/${capture_id}-${source_stem}-${stamp}.trace"
summary_path="$output_dir/${capture_id}-${source_stem}-${stamp}-summary.txt"

{
    print "capture=${capture_id}-simultaneous-batch-export-and-editing"
    print "source=$source_path"
    print "configuration=Release"
    print "commit=$(git -C "$repo_root" rev-parse HEAD)"
    print "os=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    print "hardware=$(system_profiler SPHardwareDataType -detailLevel mini | tr '\n' ';')"
    print "raw_decoder=CIRAWFilter via ImageDecoder.load"
    print "raw_decoder_version=system Core Image; identify with the OS build above"
    print "batch_items=$item_count"
    print "editing_gestures=$gesture_count"
    print "supporting_work=histogram enabled per confirmed settled frame; comparison and prefetch disabled"
    print "cache_state=warm (settled preview develop completed before the measured phase)"
    print "trace=$trace_path"
    print ""
} > "$summary_path"

# Build the test bundle before tracing. Tracing `swift test` directly also traces compilation,
# producing a huge system trace unrelated to the benchmark.
print "Preparing Release XCTest bundle..." >> "$summary_path"
"$swift_path" test -c release --filter ConcurrentExportEditingBenchmark/testRealConcurrentBatchExportAndEditing \
    >> "$summary_path" 2>&1
bin_path="$($swift_path build -c release --show-bin-path)"
test_bundle="$bin_path/LumoPackageTests.xctest"
if [[ ! -d "$test_bundle" ]]; then
    print -u2 "Release test bundle does not exist: $test_bundle"
    exit 2
fi
print "test_bundle=$test_bundle" >> "$summary_path"

xctrace record \
    --template "Metal System Trace" \
    --instrument "Points of Interest" \
    --output "$trace_path" \
    --time-limit "$time_limit" \
    --env LUMO_CONCURRENT_CAPTURE=1 \
    --env "LUMO_CONCURRENT_CAPTURE_RAW=$source_path" \
    --env "LUMO_CONCURRENT_CAPTURE_ITEMS=$item_count" \
    --env "LUMO_CONCURRENT_CAPTURE_GESTURES=$gesture_count" \
    "${secondary_env[@]}" \
    --target-stdout - \
    --launch -- \
    "$xctest_path" -XCTest ConcurrentExportEditingBenchmark/testRealConcurrentBatchExportAndEditing "$test_bundle" \
    >> "$summary_path" 2>&1

print "trace=$trace_path"
print "summary=$summary_path"
