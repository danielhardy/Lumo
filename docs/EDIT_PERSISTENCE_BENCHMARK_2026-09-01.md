# Coalesced edit-persistence benchmark — September 1, 2026

The opt-in `EditPersistenceBenchmarkTests.testEditedCatalogSizes` benchmark was run with
`LUMO_PERSISTENCE_BENCHMARK=1 swift test --filter EditPersistenceBenchmarkTests`. It seeds a valid
schema-1 catalog, applies 101 sustained edits to one photo, forces a flush, switches sources, and
measures a final termination-style flush. `writes` and `bytes` are the store's durable counters;
`peakQueue` is the maximum number of dirty asset snapshots; CPU includes user and system time for
the benchmark process. These values are a local baseline, not a cross-machine performance gate.

Hardware/OS/configuration: Apple M1 Pro, 10 CPU cores, 16 GB RAM, arm64, macOS 26.6 (25G72), Swift
6.3.3, debug `swift test`, checkout commit `7e8308a`, generated 32×24 PNG sources, 10/1,000/10,000
seeded JSON records, warm process. The 10,000-record case writes roughly 14 MB per catalog
replacement, which explains the near-linear growth in CPU, source-switch, and flush time.

| Edited-photo catalog | Writes | Bytes | Peak queue | CPU (ms) | Source switch (ms) | Termination flush (ms) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 1 | 16,475 | 1 | 25.38 | 13.00 | 4.08 |
| 1,000 | 1 | 1,401,219 | 1 | 347.01 | 23.52 | 117.05 |
| 10,000 | 1 | 14,019,229 | 1 | 3,377.02 | 227.85 | 1,250.33 |

The regression suite covers an injected 400 ms in-flight write (forced flush waits for it), an
injected first-write failure (the dirty snapshot survives for retry), and a multi-checkpoint
gesture (more than one intermediate durable write before mouse-up). The benchmark is intentionally
opt-in so ordinary CI does not incur the 10,000-record catalog cost.
