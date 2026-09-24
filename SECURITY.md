# Security policy

## Supported versions

The latest release and the `main` branch. This is a single-player offline game,
not a service, so there is nothing to patch behind you — if a fix lands, take
the next release.

## What the attack surface actually is

Worth stating plainly, because it is small and unusual for a game:

**Aphelion makes no network requests of any kind** unless you configure Mission
Control with your own API key and press Ask. No telemetry, no analytics, no
update check, no crash reporting, no account. So the interesting surface is:

1. **Your API key.** Read from `APHELION_<PROVIDER>_API_KEY` (so
   `APHELION_ANTHROPIC_API_KEY` and friends), or the OS keychain, or — only if
   you opt in — an obfuscated file in your user directory. It never enters a
   save file, a solution file, a log line or a crash dump.
   [docs/MISSION_CONTROL.md](docs/MISSION_CONTROL.md) sets out where it is kept
   and what is sent with it.
2. **Files the game parses.** Solution files and mission files are JSON that a
   player may have been handed by someone else. A malformed one should produce a
   message, never a crash and never code execution. A solution file carries a
   *program* in the flight-computer ISA, which runs on a VM with no file, no
   network and no OS access, a hard instruction budget and no way to address
   memory outside its own registers — that containment is the security property,
   and a hole in it is a real bug.
3. **The release pipeline.** Builds are produced by
   `.github/workflows/release.yml` from a tagged commit, and every download has a
   SHA-256 in `SHA256SUMS.txt`. Verify with `sha256sum -c SHA256SUMS.txt`. macOS
   builds are ad-hoc signed and not notarised — that is a known gap, explained in
   [docs/PACKAGING.md](docs/PACKAGING.md), not an oversight.

## Reporting a vulnerability

Use **GitHub's private vulnerability reporting**: the Security tab on this
repository → *Report a vulnerability*. That opens a channel only the maintainers
can see. Please do not open a public issue for anything in the list above until
there is a fix.

Useful to include: what you did, what happened, what you expected, and the
platform and build. A reproducer beats a description.

Expect an acknowledgement within a week. You will be credited in the release
notes unless you would rather not be.

## Out of scope

- The file where an opted-in API key is stored is **obfuscated, not encrypted**,
  and says so in the interface. Anything already able to read your home
  directory has already won; the obfuscation is there to keep a key out of a
  screen-share or a backup grep, and nothing more.
- Editing your own save to award yourself stars. It is your save, the
  leaderboard is local, and a solution file records the run it claims so anyone
  who cares can re-fly it.
- Reports from automated scanners with no demonstrated impact on this codebase.
