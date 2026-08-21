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
