# Starter Looks

Lumo ships a deliberately small, read-only starter library in
`Sources/LumoKit/Resources/StarterLooks`. The library currently contains four original procedural
`.cube` assets:

| Category | Look |
| --- | --- |
| Monochrome | Soft Mono |
| Cinematic | Evening Cinema |
| Film-inspired | Muted Film |
| Warm slide-inspired | Warm Slide |

The names are descriptive and do not identify or imply endorsement by a camera manufacturer or film
stock. The transforms are authored in-house and distributed under Lumo's MIT License. No
third-party attribution is required; the user-visible acknowledgement is stored in
`manifest.json` and shown below the bundled Looks in the Look inspector.

## Provenance and validation

`manifest.json` is the machine-readable record of each asset's author, source, license, attribution
requirement, redistribution constraint, and approval record. Every entry must point to an included
`.cube` with a supported 3D size and exactly `LUT_3D_SIZE³` finite rows.

Validation runs while SwiftPM evaluates `Package.swift`, so `swift build` fails closed for missing
resources, malformed cubes, duplicate entries, incomplete provenance, or an approval record that is
not marked `approved`. `BundledLookLibrary.validate()` provides the same strict gate to tests and
release tooling. Runtime loading is entry-tolerant: a damaged bundled asset is reported in
`bundledLoadWarnings` and skipped without hiding healthy starter or user Looks.

Bundled Looks are tagged `Starter` and `read-only` in the Look inspector. Imported and saved Looks
remain user-owned and continue to use the existing external-folder and import behavior.
