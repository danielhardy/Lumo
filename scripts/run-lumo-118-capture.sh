#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_path="${1:-$repo_root/realworldtest/DSC07826.ARW}"
capture_id="${LUMO_CAPTURE_ID:-LUMO-118}"
iteration_count="${LUMO_METAL_BENCHMARK_ITERATIONS:-20}"
time_limit="${LUMO_CAPTURE_TIME_LIMIT:-60s}"
output_dir="${LUMO_CAPTURE_OUTPUT_DIR:-/tmp/lumo-118-capture}"
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

mkdir -p "$output_dir"
source_stem="${source_path:t:r}"
stamp="$(date +%Y%m%d-%H%M%S)"
trace_path="$output_dir/${capture_id}-${source_stem}-${stamp}.trace"
summary_path="$output_dir/${capture_id}-${source_stem}-${stamp}-summary.txt"

{
    print "capture=${capture_id}-representative-raw-metal"
    print "source=$source_path"
    print "configuration=Release"
    print "commit=$(git -C "$repo_root" rev-parse HEAD)"
    print "os=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    print "hardware=$(system_profiler SPHardwareDataType -detailLevel mini | tr '\n' ';')"
    print "raw_decoder=CIRAWFilter via ImageDecoder.load"
    print "raw_decoder_version=system Core Image; identify with the OS build above"
    print "supporting_work=not enabled by this representative capture"
    print "cache_state=single automated Release run; cold/warm comparison is optional follow-up"
    print "trace=$trace_path"
    print ""
} > "$summary_path"

# Build the test bundle before tracing. Tracing `swift test` directly also traces compilation,
# producing a huge system trace unrelated to the presentation benchmark.
print "Preparing Release XCTest bundle..." >> "$summary_path"
"$swift_path" test -c release --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark \
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
    --env LUMO_METAL_BENCHMARK=1 \
    --env LUMO_METAL_BENCHMARK_RAW="$source_path" \
    --env LUMO_METAL_BENCHMARK_ITERATIONS="$iteration_count" \
    --target-stdout - \
    --launch -- \
    "$xctest_path" -XCTest MetalPresentationBenchmark/testRealMetalPresentationBenchmark "$test_bundle" \
    >> "$summary_path" 2>&1

print "trace=$trace_path"
print "summary=$summary_path"
