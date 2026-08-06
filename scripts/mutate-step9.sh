#!/bin/bash
# Mutation check for Phase 2 Step 9.
#
# Break the code one edit at a time and confirm the *named* test fails. A mutation that fails to
# build, runs no tests, or is skipped is NOT a pass — those are reported separately, because a
# harness that folds them into "caught" silently turns a compile error into evidence of coverage.
#
# Usage: scripts/mutate-step9.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0; SURVIVED=0; NOBUILD=0; NORUN=0; SKIPPED=0
declare -a SURVIVOR_NAMES=() NOBUILD_NAMES=() NORUN_NAMES=()

# mutate <label> <file> <perl-expr> <test-filter>
mutate() {
  local label="$1" file="$2" expr="$3" filter="$4"
  cp "$file" "$file.bak"
  perl -0pi -e "$expr" "$file"

  if cmp -s "$file" "$file.bak"; then
    echo "NO-OP     $label — the pattern did not match; the mutation never applied"
    NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (pattern did not match)")
    mv "$file.bak" "$file"; return
  fi

  local out
  out="$(swift test --filter "$filter" 2>&1)"
  mv "$file.bak" "$file"

  # Classify on structure, never on message text. A compiler diagnostic is
  # `file.swift:LINE:COL: error: …`; an XCTest failure is `file.swift:LINE: error: -[Suite test] …`.
  # An earlier version of this grepped for words like "cannot" and "expected" anywhere after
  # `error:`, and duly reported nine caught mutations as NO-BUILD because the *assertion messages*
  # contained those words. Scoring a caught mutation as "proves nothing" is the safe direction to be
  # wrong in, but it is still wrong.
  local ran
  ran="$(grep -oE "Executed [0-9]+ tests?" <<<"$out" | head -1 | grep -oE "[0-9]+")"

  if [[ -z "${ran:-}" ]]; then
    if grep -qE "^[^ ]+\.swift:[0-9]+:[0-9]+: error:" <<<"$out" || grep -q "error: fatalError" <<<"$out"; then
      echo "NO-BUILD  $label — did not compile, so this mutation proves nothing"
      NOBUILD=$((NOBUILD+1)); NOBUILD_NAMES+=("$label")
    else
      echo "NO-TESTS  $label — the suite never ran under filter '$filter'"
      NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (suite did not run)")
    fi
    return
  fi

  if [[ "$ran" == "0" ]]; then
    echo "NO-TESTS  $label — no tests matched filter '$filter'"
    NORUN=$((NORUN+1)); NORUN_NAMES+=("$label (filter matched nothing)")
    return
  fi

  if grep -qE "with [0-9]+ tests? skipped and 0 failures" <<<"$out" && ! grep -q "with [0-9]* failures" <<<"$out"; then
    echo "SKIPPED   $label — the test skipped rather than running"
    SKIPPED=$((SKIPPED+1))
    return
  fi

  if grep -qE "Executed [0-9]+ tests?, with [1-9]" <<<"$out"; then
    echo "caught    $label"
    PASS=$((PASS+1))
  else
    echo "SURVIVED  $label — '$filter' still passed with the code broken"
    SURVIVED=$((SURVIVED+1)); SURVIVOR_NAMES+=("$label -> $filter")
  fi
}

VM=Sources/LUTzyKit/ViewModels/AppViewModel.swift
DC=Sources/LUTzyKit/ViewModels/DeriveCoordinator.swift
CL=Sources/LUTzyKit/Models/CubeLUT.swift
LL=Sources/LUTzyKit/Models/LUTLibrary.swift
DR=Sources/LUTzyKit/Models/DerivedLUTRegistry.swift
RE=Sources/LUTzyKit/Models/RenderEngine.swift

echo "=== identity ==="
mutate "CubeLUT: derived id back to a UUID" "$CL" \
  's/Self\.derivedID\(name: name, table: table\)/"derived:\/\/\\(name)\/\\(UUID().uuidString)"/' \
  "LUTIDTests|CubeLUTTests|AppViewModelTests"
mutate "CubeLUT: drop the name from the derived id" "$CL" \
  's/return "derived:\/\/\\\(name\)\/\\\(hex\)"/return "derived:\/\/\\(hex)"/' \
  "LUTIDTests|CubeLUTTests"
mutate "CubeLUT: hash a constant instead of the table" "$CL" \
  's/SHA256\.hash\(data: table\)/SHA256.hash(data: Data([0]))/' \
  "LUTIDTests|CubeLUTTests"

echo "=== derive names its LUT ==="
mutate "DeriveCoordinator: name the LUT after the scratch file again" "$DC" \
  's/CubeLUT\(cube: cube, size: size, name: name, category: "Derived"\)/CubeLUT(cube: cube, size: size, name: name, category: "Derived", sourceURL: FileManager.default.temporaryDirectory.appendingPathComponent("\\(name).cube"))/' \
  "AppViewModelTests|PreviewCutoverTests|DeriveCoordinatorTests"

echo "=== the registry ==="
mutate "AppViewModel: stop registering derived LUTs on select" "$VM" \
  's/if let lut, lut\.lutID\.isDerived \{ derivedRegistry\.register\(lut\) \}//' \
  "AppViewModelTests|PreviewCutoverTests"
mutate "AppViewModel: resolve from the library only" "$VM" \
  's/if let registered = derivedRegistry\.lut\(for: id\) \{ return registered \}//' \
  "AppViewModelTests|PreviewCutoverTests"
mutate "Registry: register is a no-op" "$DR" \
  's/luts\[lut\.lutID\] = lut//' \
  "AppViewModelTests|PreviewCutoverTests"
mutate "Registry: lookup always misses" "$DR" \
  's/^        luts\[id\]$/        nil/m' \
  "AppViewModelTests|PreviewCutoverTests"

echo "=== the save ==="
mutate "AppViewModel: do not adopt the saved LUT at all" "$VM" \
  's/self\.adoptSavedLUT\(at: destination\)//' \
  "AppViewModelTests"
mutate "AppViewModel: do not re-point the document" "$VM" \
  's/        document\.lut\.lutID = saved\.lutID\n//' \
  "AppViewModelTests"
mutate "AppViewModel: re-point unconditionally (steal a foreign selection)" "$VM" \
  's/guard let current = document\.lut\.lutID, current == derive\.derivedLUT\?\.lutID else \{ return \}//' \
  "AppViewModelTests"
mutate "AppViewModel: skip registering the saved LUT" "$VM" \
  's/        derivedRegistry\.register\(saved\)\n//' \
  "AppViewModelTests"

echo "=== cache invalidation ==="
mutate "LUTLibrary: never fire onScanned" "$LL" \
  's/            self\.onScanned\?\(\)\n//' \
  "AppViewModelTests"
mutate "AppViewModel: do not wire onScanned to the engine" "$VM" \
  's/            Task \{ await engine\.invalidateLUTCache\(\) \}//' \
  "AppViewModelTests"
mutate "RenderEngine: invalidateLUTCache does nothing" "$RE" \
  's/        lutCache\.removeAll\(\)\n//' \
  "RenderEngineTests"

echo "=== harder: things a shallow test would miss ==="
# Does anything notice that the re-pointed document has to re-render? The saved cube is the %.6f
# rounded copy, so this is the moment the screen should start showing what the file actually holds.
mutate "AppViewModel: re-point but never re-render" "$VM" \
  's/        document\.lut\.lutID = saved\.lutID\n        schedulePreview\(\)/        document.lut.lutID = saved.lutID/' \
  "AppViewModelTests|PreviewCutoverTests"
# A scan that fails still changed the folder under the cache.
mutate "LUTLibrary: fire onScanned only when the scan succeeded" "$LL" \
  's/            \/\/ After publishing, and on the failure path too.*\n.*\n            self\.onScanned\?\(\)/            if self.scanError == nil { self.onScanned?() }/' \
  "AppViewModelTests|LibraryScanTests"
# Halve the digest. The golden literal should object; nothing else can.
mutate "CubeLUT: 32-bit digest instead of 64" "$CL" \
  's/digest\.prefix\(8\)/digest.prefix(4)/' \
  "LUTIDTests|CubeLUTTests"
# Deliberate equivalence control. Two jobs: it proves this harness can still report SURVIVED (an
# all-caught run is otherwise indistinguishable from a broken classifier), and it is a genuine
# equivalence rather than a gap.
#
# Why equivalent, established by inspection rather than assumed:
#   - A `derived://` ID can never be in the library. `LUTLibrary.scanSync` only builds
#     `CubeLUT(url:)`, whose ID is a filesystem path. Pinned by
#     `LUTIDTests.testAScannedLibraryNeverProducesADerivedID`.
#   - For a *saved* LUT both sides hold a value parsed from the same file, so the tables are
#     identical, and `CubeLUT` compares by ID.
#   - The only field that differs is `category` ("Derived" vs the scanned folder name), and nothing
#     reads `category` off a resolved LUT — the sidebar groups by `library.categories`. Verified by
#     grep over Sources.
# So the order is unobservable. Do NOT "fix" this by tightening a test until it fails; that would be
# asserting an implementation detail.
mutate "CONTROL (expected to survive): resolve library-first instead of registry-first" "$VM" \
  's/        if let registered = derivedRegistry\.lut\(for: id\) \{ return registered \}\n        return library\.allLUTs\.first\(matching: id\)/        if let fromLibrary = library.allLUTs.first(matching: id) { return fromLibrary }\n        return derivedRegistry.lut(for: id)/' \
  "AppViewModelTests|PreviewCutoverTests|LUTIDTests"

echo "=== the derive gate ==="
mutate "RenderPipeline: derive gate — LUT stage skipped in the pipeline" \
  Sources/LUTzyKit/Models/RenderPipeline.swift \
  's/return applyLUT\(document\.lut, lut: lut, to: adjusted, space: space, cache: lutCache\)/return adjusted/' \
  "DeriveInvarianceTests"

echo
echo "================ summary ================"
echo "caught:     $PASS"
echo "SURVIVED:   $SURVIVED"
echo "NO-BUILD:   $NOBUILD   (proves nothing — fix the mutation)"
echo "NO-TESTS:   $NORUN     (proves nothing — fix the filter/pattern)"
echo "SKIPPED:    $SKIPPED   (proves nothing — fixture missing)"
for n in "${SURVIVOR_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  survived: $n"; done
for n in "${NOBUILD_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  no-build: $n"; done
for n in "${NORUN_NAMES[@]:-}"; do [[ -n "$n" ]] && echo "  no-tests: $n"; done
[[ $SURVIVED -eq 0 && $NOBUILD -eq 0 && $NORUN -eq 0 ]] || exit 1
