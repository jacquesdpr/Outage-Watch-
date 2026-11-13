# Marite Connect

Internal iPhone app for Marite Property Administrators staff: channel chat
with confirmable tagged tasks, a shared legal document library, and a
Sectional Title Assistant grounded in the STSMA and CSOS rulings.

Runs on exactly two outside parties: **Apple** (CloudKit, built into every
iPhone app) and **Anthropic** (Claude, for the Legal Assistant). No
Microsoft 365, no Azure, no custom server.

- **Chat**: channels sync between staff phones via Apple's CloudKit — no
  backend to run. Standard channels for everyone, private channels for
  listed members.
- **Tasks**: @mention someone in a message and it becomes a tracked item
  they must mark "Done" — visible inline and in **My Tasks**.
- **Push notifications**: tagging someone pushes an alert to their phone,
  handled entirely by CloudKit — no APNs key or server to manage.
- **Legal Library**: PDFs (the Act, regulations, CSOS orders) synced via
  CloudKit; add one from any phone and everyone's copy updates.
- **Legal Assistant**: asks Claude directly, grounded in text PDFKit
  extracts on-device from the Legal Library.

Two ways to get this open in Xcode:

- **No git, just clicking and pasting**: **[PASTE_IN_XCODE.md](PASTE_IN_XCODE.md)**.
- **The organized, multi-file project** (needs one Terminal command):
  **[HANDOFF.md](HANDOFF.md)**.

Either way, next read **[docs/SETUP.md](docs/SETUP.md)** for the CloudKit
container/schema setup and getting a Claude API key. See
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for how the pieces fit
together, and the two tradeoffs worth knowing about (soft-enforced private
channels, and the Claude key shipping inside the app).

## Layout

```
MariteConnect/
├── project.yml                  # XcodeGen spec — run `xcodegen generate` to produce the .xcodeproj
├── Sources/MariteConnect/       # SwiftUI app
│   ├── App/                     # entry point, config, root navigation
│   ├── CloudKit/                # CloudKitManager: account status, identity
│   ├── Models/                  # CKRecord <-> Swift struct mapping
│   ├── Services/                # Chat / Task / Staff directory / Legal library / Assistant / Push
│   ├── Features/                # SwiftUI screens, one folder per tab
│   └── Common/                  # shared UI components
├── MariteConnectAllInOne.swift   # same app, one file, for the paste-in-Xcode path
├── PASTE_IN_XCODE.md
├── HANDOFF.md
└── docs/
    ├── SETUP.md
    └── ARCHITECTURE.md
```

This project was scaffolded without access to Xcode, a Mac, or the CloudKit
Dashboard — open it in Xcode and follow docs/SETUP.md to build, run, and
iterate from here.
