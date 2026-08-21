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
