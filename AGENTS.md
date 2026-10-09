# AudioPriorityBar agent guide

## Verify

- One-time per clone: `lefthook install` (enables the pre-push gate).
- Before pushing: `make check-local` runs `swift test`, `make build` and `git diff --check`. It does not install or launch the app.
- Model, reorder, mute-ledger and persistence changes: `swift test` alone is the fast check.
- `make test-hosted` kills the running app, then runs hosted Xcode tests. Manual only; no gate calls it.
- `make dev` kills the running app, replaces the copy in `~/Applications` and launches it. It can change audio routing.
- Physical routing and Bartender placement need an attended check on the installed app. Fake-service hosted tests do not prove them.

## Ownership

- `AudioPriorityBar/Models/`: UID identity, categories, reorder and mute decisions.
- `AudioPriorityBar/Services/AudioDeviceService.swift`: CoreAudio behind `AudioDeviceServicing`.
- `AudioPriorityBar/Services/PriorityManager.swift`: UserDefaults priorities.
- Mute intent is keyed by device UID. A refused mute stays known audible. Releasing the all-output latch keeps per-device mutes.
