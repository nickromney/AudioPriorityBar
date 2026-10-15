---
name: verify-audio-priority-bar
description: Run Audio Priority Bar's core pre-check and fake-device menu-bar UI journey.
---

# Verify Audio Priority Bar

Use make verify-dry-run to preview or make verify to run the Swift core tests as a pre-check, build the macOS app, and run the AudioPriorityBarUITests menu-bar journey. The app is built with the throwaway bundle id `com.example.AudioPriorityBar.verify`, isolating UserDefaults from the owner's app. The UI journey launches with `--verify-ui`, which selects synthetic devices whose CoreAudio setters are no-ops and also shows the status-item panel in an ordinary window (so the journey does not depend on free menu-bar space). It asserts the status item is installed, moves a fake device up, and asserts the displayed priority order changes. The real app preferences plist is hashed before and after; any change fails verification. SwiftPM scratch data and Xcode DerivedData are isolated under verify-kit run state. Logs and the result bundle are retained as evidence.

This proves core model/service tests, app compilation, and the panel's device-ordering journey against fake devices. It does not click the menu-bar icon itself. The fake provider does not test physical routing, real-device muting, or Bartender placement; those remain attended checks on the installed app.
