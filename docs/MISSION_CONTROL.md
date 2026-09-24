# Mission Control

An optional co-pilot. You radio it an intent in English; it proposes
instructions in the flight computer's language; you read them, change them, and
decide whether to fly them.

**Aphelion is complete without it.** Every mission has a reference solution that
was written and flown by hand, there is no account to make, no server of ours to
talk to, and with no key configured the panel shows a short explanation and
nothing else changes.

## It is allowed to be wrong

That is the feature.

Instructing a machine in English is interesting precisely because English is
imprecise and machines are not. "Circularise at apoapsis" is a complete order.
"Make the orbit round" is not — round at what altitude, using which apsis, at
what throttle?

A helpful assistant would quietly pick sensible answers and hand back a
manoeuvre that works. This one is instructed not to. It is told to:

- translate what you actually said, not what you probably meant;
- when something is unstated, take the most literal reading rather than
  inferring or asking;
- declare every such choice in an `assumptions` list;
- never silently correct an order that is physically wrong — write the burn you
  asked for, and say what it will actually do.

So a vague order comes back with a long list of assumptions and a manoeuvre that
is wrong in exactly the way that list predicts. You can see it before you fly it.
Auto-correcting that away would remove the only reason the feature exists.

Two orders, same ship, same moment:

> **"make the orbit round"**
> assumptions: *you did not say at what altitude, so I used the altitude you are
> at now; you did not say which apsis, so I burn at the next one, which is
> periapsis; you did not give a throttle, so I used full.*
> — a full-throttle burn at periapsis, which raises apoapsis. The orbit gets
> less round.

> **"circularise at apoapsis at 100 km, quarter throttle"**
> assumptions: *none.*
> — three instructions, and it works.

## Setting it up

Settings → Mission Control. Four providers: Anthropic, OpenAI, Google Gemini and
Ollama (local, no key). You supply the key and you pay for the calls.

### Where your key is kept

Aphelion never sees your key except to put it in a request header to the
provider you chose. It is never written into a save file, a solution file, a log
line or a crash report. Three sources are tried, best first:

1. **An environment variable** — `APHELION_ANTHROPIC_API_KEY`,
   `APHELION_OPENAI_API_KEY`, `APHELION_GEMINI_API_KEY`. Nothing is stored by
   the game at all. This is the recommended setup.
2. **The OS keychain**, via the tool your platform already ships — `security` on
   macOS, `secret-tool` (libsecret) on Linux. Windows has no equivalent a game
   can drive without an extra dependency, so this option is not offered there
   and the settings screen says so rather than pretending.
3. **A local file**, only if you explicitly opt in. It is obfuscated, not
   encrypted; anyone with your user directory can read it. The settings screen
   says that in those words before you can turn it on.

### Models go stale; the setting does not

A model string baked into a shipped game breaks the moment the provider retires
it. So the model is a setting, it is editable, the defaults are only defaults,
and a "model not found" response is turned into a message that names the model
and points at the setting. Where the provider offers a models endpoint, the
settings screen can list the live options rather than making you guess.

The Anthropic default is `claude-opus-5`. Nothing in Aphelion downgrades your
model to save you money — it is your key and your call.

## Offline, always

The simulation, the editor, the missions, the leaderboard and the solution files
have no network path of any kind. The only outbound request Aphelion ever makes
is the one you trigger by pressing Ask, to the provider you configured. There is
no telemetry, no analytics, no update check and no crash reporting.

## For contributors

| file | does |
| --- | --- |
| `scripts/ai/key_store.gd` | where the key lives, and nowhere else |
| `scripts/ai/ai_provider.gd` | the four wire formats; add a provider by adding one entry |
| `scripts/ai/mission_control.gd` | the prompt, the request, the history |
| `scripts/ai/proposal.gd` | parsing a reply, and assembling it so a bad suggestion is visibly bad |

The language reference in the prompt is **generated from `ISA.OPS` and
`ISA.SENSORS`**, not written out by hand, so the co-pilot can never be told
about an instruction the VM does not have or miss one it does. Add an opcode and
the prompt updates itself.

Adding a provider means one entry in `AIProvider.SPECS` plus a case in
`build_body()` and `extract_text()`. Everything else — key storage, error
messages, the panel, history — is shared.
