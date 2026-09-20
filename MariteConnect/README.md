# Marite Connect

Internal iOS/iPadOS app for Marite Property Administrators staff: channel
chat with confirmable tagged tasks, SharePoint search, and a Sectional Title
Assistant grounded in the STSMA and CSOS rulings.

- **Chat** rides on Microsoft Teams channels in your existing Microsoft 365
  tenant — standard channels for everyone, private channels for restricted
  groups.
- **Tasks**: @mention someone in a message and it becomes a tracked item
  they must mark "Done" — visible inline and in a personal **My Tasks** tab.
- **Search** hits Microsoft Graph Search across SharePoint, respecting each
  person's own existing permissions.
- **Legal Assistant** answers sectional title questions and scenarios,
  grounded in documents you upload to a dedicated SharePoint library, via a
  small serverless relay that talks to Claude.
- **Push notifications**: the moment someone tags you, you get an alert on
  your phone — tapping it opens the right channel.

Two ways to get this open in Xcode:

- **No git, just clicking and pasting**: **[PASTE_IN_XCODE.md](PASTE_IN_XCODE.md)**
  — create a new Xcode project yourself and paste in one file
  (`MariteConnectAllInOne.swift`) containing the whole app.
- **The organized, multi-file project** (needs one Terminal command):
  **[HANDOFF.md](HANDOFF.md)**.

Either way, next read **[docs/SETUP.md](docs/SETUP.md)** for the one-time
Microsoft 365/Entra ID/Azure configuration that makes it actually work
against Marite's tenant. See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**
for how the pieces fit together and why.

## Layout

```
MariteConnect/
├── project.yml                  # XcodeGen spec — run `xcodegen generate` to produce the .xcodeproj
├── Sources/MariteConnect/       # SwiftUI app
│   ├── App/                     # entry point, config, root navigation
│   ├── Auth/                    # MSAL sign-in
│   ├── Graph/                   # Microsoft Graph REST client
│   ├── Models/                  # Codable wire types
│   ├── Services/                # Chat / Task / Search / Assistant / Push business logic
│   ├── Push/                    # APNs registration, deep-link routing
│   ├── Features/                # SwiftUI screens, one folder per tab
│   └── Common/                  # shared UI components
├── ServerlessBackend/
│   └── marite-functions/        # Azure Function App: legal assistant relay + push notifications
├── HANDOFF.md                   # how to open/build this in Xcode
└── docs/
    ├── SETUP.md
    └── ARCHITECTURE.md
```

This project was scaffolded without access to Xcode or a Mac — open it in
Xcode to build, run, and iterate from here.
