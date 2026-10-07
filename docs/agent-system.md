# AudioPriorityBar: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Choose connected audio devices from persisted user priorities while preserving explicit manual intent.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [README.md](../README.md)
- [TESTING.md](../TESTING.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [AudioPriorityBar/Models/](../AudioPriorityBar/Models) | UID identity, categories, reorder and mute decisions |
| [AudioPriorityBar/Services/AudioDeviceService.swift](../AudioPriorityBar/Services/AudioDeviceService.swift) | CoreAudio reads/writes behind AudioDeviceServicing |
| [AudioPriorityBar/Services/PriorityManager.swift](../AudioPriorityBar/Services/PriorityManager.swift) | UserDefaults priorities |
| [AudioPriorityBar/AudioPriorityBarApp.swift](../AudioPriorityBar/AudioPriorityBarApp.swift) | Resident AudioManager, lifecycle and status item |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Device identity and preference migration use explicit UID evidence; name similarity alone cannot prove identity.
- Custom mode disables automatic routing.
- Visible sections do not alter routing/category semantics.
- Hosted UI tests are distinct from live device proof.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `swift test` | Isolated model/persistence tests; no live CoreAudio target |
| `make build` | Debug build; no install/launch |
| `make test` | Kills running AudioPriorityBar then launches hosted Xcode tests |
| `make dev` | Kills existing app, replaces ~/Applications bundle and launches; may change audio routing |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

### TESTING.md

Verification selection: start with `swift test` for model, reorder, mute-ledger and persistence changes. `make build` compiles the app without replacing or launching the installed copy. `make test` terminates the running app before hosted tests; it is a lifecycle effect as well as verification. Fake-service hosted renders do not prove physical device routing or Bartender placement. Record those manual observations with date, installed identity and device context.

## Executable local contract — 7 October 2026

`make test-domain` enters MuteLedgerTests and proves testMuteAllLatchCoversOutputsButNotInputs; testReleasingTheLatchKeepsIndividuallyMutedDevicesMuted; testADeviceThatRefusedTheMuteIsReportedAsStillAudible. `make test-core` runs the full SwiftPM fixture suite. `make check-local` is the mandatory Lefthook pre-push gate and includes the existing full quality/build checks without installing or launching the resident app. Hardware, permissions and hosted app checks remain separate explicit actions.

Mute intent is keyed by device UID and retained separately from hardware readback: refused output remains known audible. Releasing the all-output latch preserves explicit per-device mute; releasing it is distinct from clearing every intent.

The source-bound action/learning descriptor is [.agent/contract.json](../.agent/contract.json). A changed source or test invalidates the applicable lesson; re-run the named domain proof before retaining new guidance. Dependency resolution uses a seven-day cooldown for active update managers and uv tooling; existing locked app dependencies are retained.
