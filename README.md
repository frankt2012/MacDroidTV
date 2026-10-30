# Google TV Remote for macOS

A native SwiftUI menu bar app and interactive desktop widget for Google TV / Android TV.

- Menu bar popover with a full remote: D-pad, OK, back, home, menu, TV, settings,
  volume, mute, power, and media transport keys.
- Small and medium widgets with a working D-pad, volume, mute, power, and live
  power/volume status.
- Direct implementation of the Google TV Remote protocol v2 (TLS + protobuf),
  with no Python or ADB dependency.
- Pairing certificate and TV list are shared between the app and widget through
  a macOS App Group container.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later (Swift 5.9)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and install

```sh
cd GoogleTVRemote
xcodegen generate
xcodebuild \
  -project GoogleTVRemote.xcodeproj \
  -scheme GoogleTVRemote \
  -configuration Debug \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build
```

The app is a menu bar-only app (`LSUIElement`), so it does not appear in the Dock.

To install it for normal use:

```sh
rm -rf ~/Applications/GoogleTVRemote.app
ditto build/Build/Products/Debug/GoogleTVRemote.app ~/Applications/GoogleTVRemote.app
open ~/Applications/GoogleTVRemote.app
```

Then open the menu bar icon and pair a TV. To add the widget, open Notification
Center (or right-click the desktop and choose **Edit Widgets**) and add
**Google TV Remote**. The widget reads the app's shared state, so pair at least
one TV first.

## Signing and the App Group

The project uses automatic signing with the team in `project.yml`
(`DEVELOPMENT_TEAM`). Change that value to your own team if you fork this.

macOS has one important difference from iOS: **App Group identifiers must start
with the team identifier.** This project uses:

```text
BJB8XCZ8X9.group.com.franktriolo.googletvremote
```

A bare `group.com.…` identifier still makes
`containerURL(forSecurityApplicationGroupIdentifier:)` return a path, but every
write is then rejected by the sandbox with “You don't have permission to save
the file…”. If you change teams, update the identifier in all of these places:

- `GoogleTVRemote/GoogleTVRemote.entitlements`
- `TVRemoteWidget/TVRemoteWidget.entitlements`
- `Packages/TVRemoteKit/Sources/TVRemoteKit/Storage/SharedStore.swift`
- `project.yml` (`DEVELOPMENT_TEAM`)

If your signing setup rejects the entitlement, enable the App Group capability
for both bundle identifiers in the Apple Developer portal; Xcode's automatic
signing then creates the necessary profile when you build with
`-allowProvisioningUpdates`. A local development build with the team-prefixed
identifier works without an embedded profile in this project.

## Local network permission

The first time the app discovers or connects to a TV, macOS asks for local
network access. Allow it. Both the app and widget declare
`NSLocalNetworkUsageDescription` and browse `_androidtvremote2._tcp`; if access
is denied, discovery and commands fail even though pairing data is intact.

## How pairing works

1. The app creates a self-signed RSA-2048 client certificate on first use. The
   certificate and private key are stored in the shared state file.
2. It connects to the TV on port **6467** over TLS and sends a pairing request.
3. The TV displays a six-character code. Enter it in the app.
4. The pairing secret is derived from the client and server RSA moduli and the
   code; the TV verifies it and the certificate is remembered.
5. Commands use port **6466**. The app answers the TV's `RemoteConfigure` /
   `RemoteSetActive` handshake and then injects key events.

The TV list, active device, cached power/volume state, and identity live in
`state.json` inside the App Group container. The widget never reads the private
key for display; it only uses it when sending a command.

## Project layout

```text
GoogleTVRemote/                 Menu bar app (SwiftUI, AppModel, views)
TVRemoteWidget/                 WidgetKit extension
Packages/TVRemoteKit/           Shared protocol, crypto, storage, intents
  Sources/TVRemoteKit/
    Crypto/                     RSA key generation, DER/X.509, pairing secret
    Intents/                    Widget App Intents
    Model/                      Shared Codable models
    Proto/                      Hand-rolled protobuf encode/decode
    Protocol/                   TLS framing, pairing, command connection
    Storage/                    App Group JSON store
  Tests/TVRemoteKitTests/       30 unit tests
project.yml                     XcodeGen project definition
```

## Diagnostics

The app binary has three terminal flags that are useful when the UI cannot show
what is happening:

```sh
APP="$HOME/Applications/GoogleTVRemote.app/Contents/MacOS/GoogleTVRemote"

"$APP" --diagnose      # container path, device count, identity presence, save errors
"$APP" --write-test    # writes and reads back a marker, then restores state
"$APP" --reset-state   # deletes the shared state file
```

`--diagnose` deliberately does not print the state file, because it contains the
pairing private key.

## Tests

```sh
cd Packages/TVRemoteKit
swift test
```

The tests cover protobuf round-trips, key-injection bytes, certificate
generation, identity recreation, and pairing-secret derivation.

## Status and limitations

- Built and unit-tested, but **not yet exercised against a physical Google TV**
  in this environment. Pairing and command behavior are implemented from the
  documented protocol and the `androidtvremote2` reference implementation.
- The widget's App Intent buttons require macOS 14+ and a signed build; they do
  not work in Xcode Previews.
- This is a personal-use project, not an App Store submission. Hardened runtime
  is disabled and the app is signed for local development.
