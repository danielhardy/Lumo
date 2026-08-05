# CLAUDE.md — project guidance for AI agents

LUTzy is a native **macOS 14+** app (Swift 5.9, SwiftUI + Core Image, **zero third-party dependencies**) that applies `.cube` 3D LUTs to RAW/DNG and standard images, and can derive a `.cube` LUT from a (RAW, JPG) pair.

## Build / run / test

- Build: `swift build`
- Run (fast iteration; no sandbox/icon): `swift run`
- Full app (icon + App Sandbox): open `Package.swift` in Xcode and Run.
- Tests: `swift test`. CI runs debug build → tests → release build.

**CI's SDK is the build contract, not yours.** CI is Xcode 15.4 / Swift 5.10 against the **macOS 14.5
SDK**. A current Xcode will happily compile API that simply does not exist there — and `#available`
cannot rescue it, because an availability check gates a call at runtime and cannot conjure a symbol
the SDK never declared. Before pushing anything that touches a system framework, typecheck against
the oldest SDK on the machine:

```bash
swiftc -typecheck -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
    -target arm64-apple-macosx14.0 -swift-version 5 $(find Sources/LUTzyKit -name '*.swift')
```

This caught a `CIRAWFilter` property in Phase 2 Step 2 that built clean locally and broke CI.

## Layout

The package is split so the app's code is testable (`@testable` can't import an executable target):

- `Sources/LUTzyKit/` — everything of substance (Models, ViewModels, Views). Only `ContentView` and
  `LUTzyCommands` are `public`; keep the rest internal.
- `Sources/LUTzy/` — the `@main` entry point, `AppDelegate`, and the asset catalog. Nothing else belongs here.
- `Tests/LUTzyKitTests/` — XCTest. **Fixtures are generated, never committed** (`Fixtures.swift` builds
  `.cube` files and orientation-tagged JPEGs into a temp dir); LUTzy's real inputs are tens of MB.

When a test needs something currently `private`, widen it to internal with a comment saying why —
`RecipeExtractor.buildCube` and `workingSize` are the precedent.

Constraints that must hold: **macOS 14 minimum**, **zero third-party dependencies** (Apple frameworks only). Don't introduce SPM/CocoaPods/Carthage deps.

## Agent & workflow safety (READ THIS)

A prior multi-agent **spec/analysis** run was meant to be read-only but a sub-agent edited tracked source as a side effect. Those edits had to be reverted and re-introduced deliberately as a reviewed PR. To prevent a repeat, these rules are binding for any agent or multi-agent workflow operating in this repo:

1. **Analysis/spec/review runs are read-only w.r.t. tracked source.** Fan-out sub-agents must NOT `Edit`/`Write`/`NotebookEdit` files under version control. They return their findings/spec **as text**; the orchestrator (main session) makes any file changes on the main tree after reviewing that text.
2. **Enforce read-only mechanically, don't just ask.** Prefer one of:
   - spawn sub-agents with a read-only agent type (e.g. `Plan`, `Explore`) — they cannot write; or
   - in a `Workflow`, restrict sub-agents to read-only tools; or
   - if a sub-agent genuinely must edit, give it **worktree isolation** (`isolation: "worktree"`, or the helper below) so it operates on a throwaway copy, never the main tree.
3. **Verify the tree after any agent run.** `git status --porcelain` must be empty (aside from intended outputs). If unexpected changes appear, stash + revert them and surface to the user rather than committing.
4. **Code changes land via the normal flow** — a branch + reviewed PR — not as a silent side effect of an analysis task. Repo-meta docs (README, LICENSE, specs, this file) may be committed directly to `main`.
5. **Don't run destructive git** (history rewrite, force-push, `stash drop/clear`, branch `-D`) without explicit user approval.

### Throwaway worktree helper

For any agent run that needs a scratch checkout it can't pollute the main tree with:

```bash
DIR=$(scripts/agent-worktree.sh create)   # prints a temp worktree path on the current HEAD
# ... point the agent/workflow at "$DIR" ...
scripts/agent-worktree.sh remove "$DIR"   # clean up when done
```

## Repo conventions

- Default branch `main`; commit messages end with the `Co-Authored-By: Claude …` trailer.
- Build artifacts (`.build/`, ~hundreds of MB), `.DS_Store`, and `.claude/` are gitignored. `.claude/` is ignored, so **shared agent guidance belongs here in `CLAUDE.md`**, not under `.claude/`.
- `docs/PHASE2_SPEC.md` is the implementation plan for the non-destructive render pipeline + RAW develop controls. It is a distillation — keep it that way; per-component transcripts belong in the PR that implements the step, not in the spec.
- `docs/CODE_REVIEW.md` records the standing review findings: what was fixed, and what is still open.
