# Paste-in-Xcode quick start

Create a fresh Xcode project yourself (a few clicks, no Terminal), paste in
one file (`MariteConnectAllInOne.swift`), flip a few switches in Xcode, and
run. No external package to add this time — CloudKit and PDFKit are both
built into iOS.

## 1. Create the project

1. Xcode → **File → New → Project** → **iOS → App**.
2. Product Name: `MariteConnect`. Interface: **SwiftUI**. Language: **Swift**.
   Uncheck "Include Tests".

## 2. Delete Xcode's two starter files

Delete the auto-created `MariteConnectApp.swift` and `ContentView.swift` —
the pasted file defines its own `@main` app entry point with the same name.

## 3. Add the one file

**File → New → File…** → Swift File → name it `MariteConnectAllInOne.swift`.
Paste in everything from that file (same folder as this one, or view it on
GitHub if you're working from a link).

## 4. Turn on iCloud (CloudKit)

1. Select the target → **Signing & Capabilities** → **+ Capability** → add
   **iCloud**.
2. Check **CloudKit** under Services. Xcode creates a container for you,
   normally named `iCloud.<your bundle ID>`.
3. Make sure that name matches `AppConfig.cloudKitContainerIdentifier` near
   the top of the pasted file, and the entitlements file Xcode generated —
   if your bundle ID isn't `com.marite.MariteConnect`, either update the
   Bundle Identifier on the **General** tab to match, or update
   `cloudKitContainerIdentifier` to match whatever container Xcode created.

## 5. Turn on Push Notifications

Same **Signing & Capabilities** tab → **+ Capability** → add **Push
Notifications**.

## 6. Set your signing team

**Signing & Capabilities** → **Team** dropdown → your Apple ID. Required to
run on a real iPhone (not needed for the Simulator, though CloudKit push
notifications don't work in the Simulator — test those on a real device).

## 7. Build and run

⌘R, target your iPhone (plugged in, or over Wi-Fi if you've set that up in
Xcode). First launch asks you to pick a display name, then shows the four
tabs: Channels, My Tasks, Library, Legal Assistant.

## What still needs setup before it's fully working

1. Fill in `AppConfig.claudeAPIKey` near the top of the pasted file with a
   real key from console.anthropic.com (and set a spending limit on it —
   see docs/SETUP.md for why).
2. Create the CloudKit schema (the record types the app expects) in the
   CloudKit Dashboard — this is the one piece of setup that's genuinely
   outside Xcode. Full field-by-field instructions:
   https://github.com/jacquesdpr/Outage-Watch-/blob/claude/marite-connect-cloudkit/MariteConnect/docs/SETUP.md

Until the schema exists, channels/messages/tasks will fail to load with a
CloudKit error — that's expected until step 2 is done.

## If you'd rather use the already-organized project instead

The same code, split into normal separate files the usual way an Xcode
project is organized, is in this same repository — see `HANDOFF.md` if
you'd rather go that route (needs one Terminal command to generate the
Xcode project file).
