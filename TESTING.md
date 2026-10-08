# Testing

Run the isolated persistence and device-model tests with:

```sh
swift test
```

The package target deliberately excludes SwiftUI and live CoreAudio code. The
app target consumes `AudioDeviceServicing`, so the next test layer can provide
a fake audio service without changing the user's devices. Build the app with:

```sh
xcodebuild -project AudioPriorityBar.xcodeproj \
  -scheme AudioPriorityBar \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/AudioPriorityBarDerivedData \
  build
```

Run the Xcode test bundle, which imports the real app module:

```sh
xcodebuild -project AudioPriorityBar.xcodeproj \
  -scheme AudioPriorityBar \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath /tmp/AudioPriorityBarTestDerivedData \
  test
```

## Quit the app before running the Xcode test bundle

`AudioPriorityBarTests` is hosted by the app itself. If a copy is already
running — normally `~/Applications/AudioPriorityBar.app` — LaunchServices
refuses to start a second instance of the same bundle identifier and the run
fails with:

```
Could not launch "AudioPriorityBarTests". The LaunchServices launcher has
returned an error.
```

This is not a broken test target. Quit the running copy first, then relaunch it
afterwards:

```sh
pkill -x AudioPriorityBar
```

`SingleInstanceGuard` is also skipped under XCTest (see `RunContext`), so the
host app no longer exits on its own lock during a test run.

## Menu bar and native UI checks

The hosted tests cover the relaunch process handoff and panel bounds in light
and dark appearances. They render controls and Settings with fake devices to
`/tmp/AudioPriorityBar-{controls,settings}-NSAppearanceName{Aqua,DarkAqua}.png`.
These are offscreen renders, not a verification of live popover interaction.

For the live Bartender check:

1. Install with `make dev`. Both Debug and Release must report
   `com.example.AudioPriorityBar` as their bundle identifier.
2. If upgrading from the old Debug test-host identity, put the new item in
   Bartender's Shown section once.
3. Mute and unmute, change devices, close and reopen the panel, and use
   Relaunch. Verify the item stays in its assigned section and only one item
   exists throughout the relaunch.
4. Repeat after quitting and launching the app and after a display change.
5. Check Command-comma, Tab/Space navigation with macOS Keyboard Navigation
   enabled, device options in Edit mode, and right-click Settings while the
   panel is open. Check VoiceOver names for selection, mute, and sliders.

The preference import deliberately excludes AppKit position and visibility
keys. Tests use isolated defaults and do not migrate the installed copy's
preferences.
