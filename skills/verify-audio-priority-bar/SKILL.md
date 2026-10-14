---
name: verify-audio-priority-bar
description: Run Audio Priority Bar's native core tests and compile the app without installing or launching it.
---

# Verify Audio Priority Bar

Use make verify-dry-run to preview or make verify to run the existing Swift core test target and build the macOS app with the installed Xcode toolchain. SwiftPM scratch data and Xcode DerivedData are isolated under verify-kit run state with two build jobs. The run retains the toolchain versions and test/build logs as evidence, then removes its scratch and app bundle.

This proves core model/service tests and that the current app source compiles. It does not launch the menu bar app, test physical audio routing, or change the installed application. Bartender placement and real-device routing remain attended checks.
