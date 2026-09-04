#!/bin/zsh
set -euo pipefail

project_root="${0:A:h}/.."
cd "$project_root"

swift_command="${SWIFT_COMMAND:-swift}"
configuration="${SWIFT_FORMAT_CONFIGURATION:-$project_root/.swift-format}"
base="${SWIFT_FORMAT_BASE:-}"

if [[ ! -f "$configuration" ]]; then
  print -u2 "Swift-format configuration is missing: $configuration"
  exit 2
fi

typeset -a files=()
if [[ -n "$base" ]] && git rev-parse --verify "$base^{commit}" >/dev/null 2>&1; then
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(git diff --name-only --diff-filter=ACMR "$base"...HEAD -- '*.swift')
else
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(git diff --name-only --diff-filter=ACMR HEAD -- '*.swift')
  while IFS= read -r file; do
    [[ -n "$file" ]] && files+=("$file")
  done < <(git ls-files --others --exclude-standard -- '*.swift')
fi

if (( ${#files[@]} == 0 )); then
  print "Swift-format: no changed Swift files"
  exit 0
fi

failed=0
for file in ${(On)files}; do
  [[ -f "$file" ]] || continue
  output="$($swift_command format lint --strict --configuration "$configuration" "$file" 2>&1)" || {
    print -u2 "Swift-format violations in $file:"
    print -u2 -- "$output"
    failed=1
  }
done

if (( failed )); then
  print -u2 "Run: swift format format --configuration $configuration --in-place <file>"
  exit 1
fi

print "Swift-format: checked ${#files[@]} changed Swift file(s)"
