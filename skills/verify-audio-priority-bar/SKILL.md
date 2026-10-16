---
name: verify-audio-priority-bar
description: Run Audio Priority Bar's core pre-check and fake-device menu-bar UI journey.
---

# Verify Audio Priority Bar

Use make verify-dry-run to preview or make verify to run the Swift core tests as a pre-check, build the macOS app, and run the AudioPriorityBarUITests menu-bar journey. The app is built with the throwaway bundle id `com.example.AudioPriorityBar.verify`, isolating UserDefaults from the owner's app. The UI journey launches with `--verify-ui`, which selects synthetic devices whose CoreAudio setters are no-ops and also shows the status-item panel in an ordinary window (so the journey does not depend on free menu-bar space). It asserts the status item is installed, moves a fake device up, and asserts the displayed priority order changes. The real app preferences plist is captured and hashed before and after. `scripts/compare-preferences.py` rejects settings or device changes. It permits only finite, nondecreasing `lastSeen` timestamp advances for the same ordered, pre-existing device records. The resident app refreshes those timestamps every 30 seconds. `preferences-comparison.json` reports this exception and explicitly records that raw bytes changed; it never claims byte invariance. SwiftPM scratch data and Xcode DerivedData are isolated under verify-kit run state. Logs and the result bundle are retained as evidence.

This proves core model/service tests, app compilation, and the panel's device-ordering journey against fake devices. It does not click the menu-bar icon itself. The fake provider does not test physical routing, real-device muting, or Bartender placement; those remain attended checks on the installed app.

## Hosted controls recipe

Run `APB_VERIFY_RECIPE=hosted make verify` to exercise the rendered SwiftUI mute
and unmute controls through AppKit accessibility. The test reads fake-service
volume after each press and checks that the output slider and mute button retain
their frames. It captures before, muted, and restored screenshots plus an action
trace. Panel size is checked in both appearances with controls and settings.
Hosted startup creates neither an AudioManager nor a status item; tests inject
fake services, which cannot request microphone access. This recipe never kills,
installs, or replaces the resident app.

## Evidence and cleanup

Set `VERIFY_EVIDENCE_ROOT` to a persistent directory and `VERIFY_RUN_ID` to a new
run ID. Evidence survives automatic cleanup under
`$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/`, including logs, `run-result.json`, and
`hosted.xcresult` or `ui.xcresult`. Hosted screenshots and action trace are in
`hosted/`. Cleanup removes only the run's scratch/build state and verification
preferences. Physical audio and Bartender checks remain attended and unverified.
See [the feature map](features/README.md) for recipe scope.

The comparator's negative regressions run with `make verify-test`, including
priority changes, added fixture UIDs, changed device content or identity, and
backward, missing, boolean, or nonfinite timestamps. Run the helper directly as
`python3 skills/verify-audio-priority-bar/scripts/compare-preferences.py BEFORE.plist AFTER.plist RESULT.json`.
