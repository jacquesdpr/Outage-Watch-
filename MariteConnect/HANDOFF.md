# Handoff: opening this project in Xcode

This project has no `.xcodeproj` committed — it's generated on your Mac from
`project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen), so the
project file never goes stale relative to the source tree and never causes
merge conflicts in git. This is the one step required before Xcode can open
anything.

## Prerequisites

- A Mac running **Xcode 15 or later** (Xcode itself isn't scriptable from
  here — this step must happen on your machine).
- [Homebrew](https://brew.sh) installed.

## Steps

```bash
# 1. Clone the repo and switch to this branch (skip if already checked out)
git clone https://github.com/jacquesdpr/Outage-Watch-.git
cd Outage-Watch-
git checkout claude/staff-chat-task-app-6dt2tj

# 2. Install XcodeGen (one-time, per machine)
brew install xcodegen

# 3. Generate the Xcode project from project.yml
cd MariteConnect
xcodegen generate

# 4. Open it
open MariteConnect.xcodeproj
```

Xcode will resolve the one Swift Package dependency (MSAL, declared in
`project.yml`) automatically on first open — this needs an internet
connection the first time.

## What you'll see build-clean vs. what still needs config

The project **builds and runs immediately** — every screen renders with
SwiftUI previews and placeholder states. It will compile as-is.

It will not do anything *real* (sign-in will fail, channels/tasks/search
will show errors) until you fill in the placeholder values in
`Sources/MariteConnect/App/AppConfig.swift` — those require the Microsoft
365 / Entra ID / Azure setup covered step by step in
**[docs/SETUP.md](docs/SETUP.md)**. That's the next document to work
through once the project is open in Xcode.

## Signing, to run on a device

In Xcode: select the `MariteConnect` target → **Signing & Capabilities** →
choose your Apple Developer **Team** (or set `DEVELOPMENT_TEAM` in
`project.yml` and re-run `xcodegen generate`). Running in the iOS
**Simulator** needs no signing at all — start there.

## Re-running xcodegen later

Run `xcodegen generate` again any time `project.yml` changes (new files are
picked up automatically via the `Sources/MariteConnect` folder reference —
you don't need to regenerate just for adding/removing `.swift` files, only
for changes to build settings, targets, or dependencies in `project.yml`
itself).
