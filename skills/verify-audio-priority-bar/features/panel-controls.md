# Panel controls

## Sub-features

Speaker ordering, output mute/unmute, volume-control geometry, and compact
controls/settings layout in light and dark appearances.

## How to get to it (user POV)

Open the status-item panel. Speakers appear in priority order. The selected
speaker has a mute button and output volume slider. Open settings for preferences.

## Driving it with Xcode

`make verify` runs the existing XCUITest against synthetic speakers, presses
`move-up-verify-speaker-b`, and asserts the new displayed order.
`APB_VERIFY_RECIPE=hosted make verify` renders the actual SwiftUI panel in an
NSHostingView, presses `Mute Desk Speakers` and `Unmute Desk Speakers` using
AppKit accessibility, reads fake device volume independently, and compares
slider/button frames before and after. A separate isolated file-lock test launches
an independent process and checks refusal while owned and acquisition after
release. Before/muted/restored screenshots and
`rendered-actions.txt` survive cleanup alongside the Xcode result bundle.

## Gotchas

The hosted app has no production controllers. Fake-service tests do not route
physical audio, prove hardware mute, or prove Bartender placement. The default
UI recipe creates a verification status item and ordinary panel window. It does
not click the menu-bar icon itself. Use a fresh run ID for every invocation.
