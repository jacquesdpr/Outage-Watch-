# Handoff: opening this project in Xcode

This project has no `.xcodeproj` committed — it's generated on your Mac from
`project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Prerequisites

- A Mac running **Xcode 15 or later**.
- [Homebrew](https://brew.sh) installed.

## Steps

```bash
git clone https://github.com/jacquesdpr/Outage-Watch-.git
cd Outage-Watch-
git checkout claude/marite-connect-cloudkit

brew install xcodegen          # one-time
cd MariteConnect
xcodegen generate              # produces MariteConnect.xcodeproj
open MariteConnect.xcodeproj
```

No Swift Package dependency to resolve this time — CloudKit and PDFKit are
both built into iOS.

## What you'll see build-clean vs. what still needs config

The project **builds and runs immediately**. It won't do anything *real*
until you:

1. Fill in `AppConfig.swift`'s two placeholders (`claudeAPIKey`,
   `cloudKitContainerIdentifier`).
2. Enable the iCloud (CloudKit) and Push Notifications capabilities in
   Xcode's Signing & Capabilities tab — `project.yml` sets up the
   entitlements file, but the CloudKit container itself has to be created
   once through Xcode's UI (it offers to do this for you the first time you
   add the iCloud capability).
3. Create the CloudKit schema in the CloudKit Dashboard.

All three are covered step by step in **[docs/SETUP.md](docs/SETUP.md)**.

## Signing, to run on a device

Target → **Signing & Capabilities** → **Team** dropdown → your Apple ID.
CloudKit push notifications don't work in the Simulator, so test on a real
iPhone.

## Re-running xcodegen later

Run `xcodegen generate` again any time `project.yml` changes (build
settings, capabilities, target config) — not needed just for adding or
removing `.swift` files.
