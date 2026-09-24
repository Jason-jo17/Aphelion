---
name: godot-export-signing
description: Exporting and signing Aphelion for Windows, macOS and Linux — headless export commands, the export presets, code signing, notarisation, and what to do when Gatekeeper or SmartScreen blocks a build. Load when working on packaging, releases or CI export jobs.
---

# Godot export and signing

Full detail: `docs/PACKAGING.md`. This is the operational summary.

## Export, headless

```sh
godot --headless --import --quit-after 200          # build .godot/ first
godot --headless --export-release "Linux"   dist/linux/Aphelion.x86_64
godot --headless --export-release "Windows" dist/windows/Aphelion.exe
godot --headless --export-release "macOS"   dist/macos/Aphelion.zip
```

All three cross-compile from Linux. The release workflow uses a container that
pins the editor and its matching export templates together, which is the part
that is fiddly by hand.

`--export-release` fails silently-ish if the templates for your exact version
are missing — check the output, and check the file is non-empty.

## Presets

`export_presets.cfg` is version-controlled so releases are reproducible. Preset
names are `Linux`, `Windows`, `macOS` and are referenced by the CI matrix; renaming
one breaks the workflow.

All three exclude `tools/refsim/`, `tests/`, `addons/gut/` and `docs/`.
`binary_format/embed_pck=true` means one file ships, not two.

## Signing

**Windows** — unsigned; SmartScreen warns until reputation builds. To sign, set
`codesign/enable=true` plus identity and password in the preset, supply the
certificate from a CI secret, write it to a temp file in the job, delete it
after. Never commit a certificate or put a password in the preset file.

**macOS** — ad-hoc signed (`codesign/codesign=1`), not notarised, because
notarisation needs a paid Apple Developer account. Gatekeeper blocks it on first
launch; the release notes say so and give the fix
(`xattr -dr com.apple.quarantine Aphelion.app`, or right-click → Open).

To notarise properly: `codesign/codesign=2`, `notarization/notarization=2`, plus
Apple ID, an app-specific password and team ID from secrets — **and move the
macOS target out of the Linux container into a `macos-latest` job**, because
notarisation must run on macOS.

**Linux** — unsigned. AppImage is the obvious next step; not built today.

## Releasing

```sh
git tag v0.1.0 && git push origin v0.1.0
```

`release.yml` runs the whole CI suite first, exports all three, writes SHA-256
checksums, and attaches everything. A release that fails its own tests is not a
release.

## When something goes wrong

| symptom | cause |
| --- | --- |
| export produces an empty file | export templates missing or version-mismatched |
| "No export template found" | template version ≠ editor version, exactly |
| missions missing at runtime | check the preset's `exclude_filter`; `missions/` must not be excluded |
| Gatekeeper refuses the .app | expected — ad-hoc signed, see above |
| SmartScreen warns | expected — unsigned |
| checksums differ between builds | the container image moved; pin it |
