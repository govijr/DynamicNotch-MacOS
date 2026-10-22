# DynamicNotch

Build polished, notch-aware surfaces for macOS apps with SwiftUI.

DynamicNotch gives you a reusable SwiftUI surface and an AppKit-backed window controller for edge-attached experiences: recording indicators, media controls, build progress, approvals, notifications, and Dynamic Island-style compact states.

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-111827?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F97316?style=flat-square" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0EA5E9?style=flat-square" alt="SwiftUI and AppKit">
</p>

## Why DynamicNotch?

Notch-based UI looks simple until window coordinates, rounded shoulders, clipping, hit testing, safe areas, and physical camera housings all meet in one component.

DynamicNotch keeps those responsibilities in the right places:

- SwiftUI owns your content.
- AppKit owns the floating window and screen geometry.
- The package clips rendering and hit testing to the same notch silhouette.
- Top and bottom windows account for the selected display's safe area.
- Compact mode reserves the physical camera housing while keeping the background continuous.

## Requirements

- macOS 13 or later
- Swift 5.9 or later
- A SwiftUI macOS app with AppKit access

## Installation

### Xcode

1. Open your app project in Xcode.
2. Select **File → Add Package Dependencies…**.
3. Paste the GitHub repository URL for DynamicNotch.
4. Choose a version or branch.
5. Add the `DynamicNotch` product to your macOS target.

Then import it:

```swift
import DynamicNotch
```

### Swift Package Manager

Add the repository as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/govijr/DynamicNotch-MacOS.git",
        from: "0.1.0"
    )
]
```

Add the product to the target that uses it:

```swift
targets: [
    .executableTarget(
        name: "YourMacApp",
        dependencies: [
            .product(name: "DynamicNotch", package: "DynamicNotch")
        ]
    )
]
```

The package is published at [github.com/govijr/DynamicNotch-MacOS](https://github.com/govijr/DynamicNotch-MacOS).

## Two ways to use it

### 1. Embed the SwiftUI surface

Use `DynamicNotch` when your app already owns the containing window:

```swift
import SwiftUI
import DynamicNotch

struct RecordingSurface: View {
    var body: some View {
        DynamicNotch(
            direction: .top,
            width: 420,
            height: 72,
            background: .black,
            contentInsets: EdgeInsets(
                top: 0,
                leading: 18,
                bottom: 0,
                trailing: 18
            )
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)

                Text("Recording")
                    .foregroundStyle(.white)

                Spacer()

                Text("00:42")
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
}
```

Supported directions are `.top`, `.bottom`, `.left`, and `.right`.

### 2. Present an edge window

Use `DynamicNotchWindowController` when the surface should float above the desktop:

```swift
import AppKit
import DynamicNotch
import SwiftUI

@MainActor
final class NotchPresenter {
    private let controller = DynamicNotchWindowController()

    func showBuildStatus() {
        controller.show(
            placement: .edge(.top, alignment: .center),
            width: 420,
            height: 72
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)

                Text("Build finished")
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 20)
        }
    }

    func hide() {
        controller.hide()
    }
}
```

Keep one controller alive for the lifetime of the feature. Calling `show` again updates the content and animates the window to its new geometry.

## Dismissal

Edge windows dismiss when the user clicks outside the notch by default. The
controller listens to clicks both inside the app and in other apps, while
clicks on the rendered notch shape continue to work normally:

```swift
let controller = DynamicNotchWindowController()

controller.onDismiss = {
    isShowing = false
}

controller.show(
    placement: .edge(.top),
    width: 420,
    height: 72
) {
    Text("Click anywhere else to dismiss")
}
```

For a surface that should stay visible until your app decides otherwise, opt
out of click-away dismissal:

```swift
controller.dismissalPolicy = .manual
```

You can dismiss a surface from a button, timer, notification, or any other
app-owned action:

```swift
controller.dismiss()
// `controller.hide()` remains available as an alias.
```

## Placement

`DynamicNotchPlacement` controls the edge, alignment, and offset:

```swift
.edge(.top, alignment: .center)
.edge(.bottom, alignment: .end, offset: -24)
.edge(.left, alignment: .start, offset: 16)
.edge(.right, alignment: .end)
```

`start`, `center`, and `end` are relative to the attached edge. Positive offsets move toward the edge's end: rightward on horizontal edges and downward on vertical edges. Placement is clamped to the selected screen.

Pass `screen:` when targeting a particular display in a multi-monitor setup. Otherwise DynamicNotch uses the main screen.

## Safe areas and physical Mac notches

The window controller automatically uses the selected screen's safe-area inset for top and bottom surfaces. This keeps expanded content below a physical camera housing and keeps bottom content away from the exposed edge.

```swift
controller.show(
    placement: .edge(.top),
    width: 420,
    height: 72
) {
    Text("Camera-safe content")
        .foregroundStyle(.white)
}
```

When using `DynamicNotch` directly, pass the inset yourself because a standalone SwiftUI view cannot infer its containing screen:

```swift
let safeTopInset = NSScreen.main?.safeAreaInsets.top ?? 3

DynamicNotch(
    direction: .top,
    width: 420,
    height: 72,
    attachedEdgeRail: safeTopInset
) {
    Text("Camera-safe content")
}
```

Set `attachedEdgeRail: 0` when you explicitly want to opt out of the automatic controller behavior.

## Compact mode

Compact mode is designed for the small, always-present state of a top notch. It provides independent leading and trailing regions and automatically measures the physical camera gap when the display exposes it.

The background remains one continuous surface; the center gap affects content layout only, so the physical notch never reveals a transparent hole.

```swift
controller.showCompact(width: 400) {
    HStack(spacing: 6) {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)

        Text("Live")
    }
    .foregroundStyle(.white)
} trailing: {
    HStack(spacing: 8) {
        Image(systemName: "waveform")
        Text("00:42")
            .monospacedDigit()
    }
    .foregroundStyle(.white.opacity(0.75))
}
```

The compact height defaults to the larger of the status-bar thickness and the display's top safe area. Override `height` or `centerGap` when you are building a fixed hardware-independent layout.

Move between modes using the same controller:

```swift
controller.showCompact(width: 400) {
    CompactLeadingView()
} trailing: {
    CompactTrailingView()
}

controller.show(
    placement: .edge(.top),
    width: 520,
    height: 180
) {
    ExpandedView()
}
```

The controller exposes `presentationMode` as `.compact` or `.expanded`.

## Geometry customization

All surfaces support a rounded exposed edge and independent shoulder curvature:

```swift
DynamicNotch(
    direction: .top,
    width: 520,
    height: 180,
    cornerRadius: 25,
    shoulderRadius: 30,
    background: .black
) {
    Text("Expanded content")
        .foregroundStyle(.white)
}
```

Use `cornerRadius` for the exposed corners and `shoulderRadius` for the inward transitions from the attached lip.

## Demo app

The package includes a menu-bar demo with no startup surface. Use the native
menu to trigger `Top`, `Bottom`, `Left`, or `Right`, hide every surface, or
quit the demo.

Run it from the package directory:

```sh
swift run DynamicNotchDemo
```

To build a normal Finder-style app bundle:

```sh
zsh Scripts/build-demo-app.sh
open dist/DynamicNotchDemo.app
```

## Scope

DynamicNotch provides the geometry, clipping, safe-area handling, placement, and presentation primitives. The consuming app owns product behavior such as:

- hover expansion
- drag gestures
- notifications and timers
- persistence
- menu-bar integration
- application-specific transitions and state

Keeping those decisions in the consuming app keeps the package small and makes it work for more kinds of macOS apps.

## Project status

DynamicNotch is currently intended for early adopters and production prototypes. The core API is stable enough to integrate, while the package continues to evolve toward a `1.0` release with broader integration and visual test coverage.

## License

DynamicNotch is available under the MIT License.

Copyright (c) 2026 Govi

See [LICENSE](LICENSE) for the full license text.
