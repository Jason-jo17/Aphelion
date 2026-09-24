# Packaging

Three desktop targets, cross-compiled from one Linux container.

## Automatic

Tag and push:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

`.github/workflows/release.yml` runs the whole CI suite first — a release that
fails its own tests is not a release — then exports Windows, macOS and Linux,
writes SHA-256 checksums, and attaches everything to a GitHub release.

## By hand

```sh
godot --headless --import --quit-after 200
godot --headless --export-release "Linux"   dist/linux/Aphelion.x86_64
godot --headless --export-release "Windows" dist/windows/Aphelion.exe
godot --headless --export-release "macOS"   dist/macos/Aphelion.zip
```

You need the export templates for your exact Godot version
(`godot --headless --export-release` will say so if you do not).

The presets live in `export_presets.cfg` and are version-controlled so a release
is reproducible. They exclude `tools/refsim/`, `tests/`, `addons/gut/` and
`docs/` — none of which a player needs.

## Signing

### Windows

Unsigned. SmartScreen will warn on first run until the binary builds reputation.

To sign, get a code-signing certificate, then set in the Windows preset:

```
codesign/enable=true
codesign/identity_type=0       # PKCS#12
codesign/identity="path/to/cert.pfx"
codesign/password="…"          # from a secret, never committed
```

In CI, put the certificate in a repository secret, write it to a temp file in
the job, and delete it afterwards. Do not commit it, and do not put the password
in `export_presets.cfg`.

### macOS

Builds are **ad-hoc signed and not notarised**. Gatekeeper refuses them on first
launch; right-click → Open, or:

```sh
xattr -dr com.apple.quarantine Aphelion.app
```

Notarisation needs a paid Apple Developer account, which this project does not
have. The release notes say so plainly rather than leaving Gatekeeper to explain
it.

If you have an account, set in the macOS preset:

```
codesign/codesign=2                          # Xcode codesign
codesign/identity="Developer ID Application: …"
notarization/notarization=2                  # notarytool
notarization/apple_id_name="…"
notarization/apple_id_password="…"           # an app-specific password
notarization/apple_team_id="…"
```

and supply the secrets from the CI environment. Notarisation must run on macOS,
so that target moves out of the Linux container into a `macos-latest` job.

### Linux

Linux binaries are not signed. An AppImage is the usual next step; it is not
built today.

## What ships

```
Aphelion.x86_64 / Aphelion.exe / Aphelion.app
LICENSE
README.md
ASSETS-LICENSE.md
```

Everything else — missions, ship data, the part catalogue — is embedded in the
binary by `binary_format/embed_pck=true`, so there is exactly one file to move.

Missions being embedded does mean a player cannot drop a new one in beside the
executable. Loadable mission packs are the obvious next step and are noted in
`docs/MISSIONS.md`.

## Reproducibility

The export container pins the Godot version and its matching export templates,
which is the fiddly part of doing this by hand. Given the same tag and the same
container image, the outputs should be byte-identical; if they are not, the
checksums in the release will say so.
