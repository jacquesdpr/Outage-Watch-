# Paste-in-Xcode quick start

The fastest way to get Marite Connect on screen: create a fresh Xcode
project yourself (a few clicks, no Terminal), paste in one file
(`MariteConnectAllInOne.swift`), add one dependency from GitHub, flip two
switches, and run. No `git`, no command-line tools required for this path.

**View or copy the one file directly on GitHub:**
https://github.com/jacquesdpr/Outage-Watch-/blob/claude/staff-chat-task-app-6dt2tj/MariteConnect/MariteConnectAllInOne.swift

## 1. Create the project

1. Open Xcode → **File → New → Project**.
2. Choose **iOS → App**, click Next.
3. Product Name: `MariteConnect`. Interface: **SwiftUI**. Language: **Swift**.
   Uncheck "Include Tests" (not needed). Choose anywhere to save it.

## 2. Delete Xcode's two starter files

Xcode auto-creates a `MariteConnectApp.swift` and a `ContentView.swift`. The
file you're about to paste in **already defines its own app entry point**
with the same name, so these two would clash with it — delete both (select
in the file list → Delete → "Move to Trash"). Keep `Assets.xcassets`.

## 3. Add the one file

1. **File → New → File…** → Swift File → name it `MariteConnectAllInOne.swift`.
2. Open it, delete the placeholder content, and paste in everything from
   `MariteConnectAllInOne.swift` (the link above, or the copy already in
   this same `MariteConnect` folder).

At this point the project **will not yet build** — it's missing the one
external dependency (MSAL) the code imports. That's step 4.

## 4. Add the MSAL package from GitHub

This is the one piece of outside code the app needs: Microsoft's own sign-in
library, so staff can log in with their Marite Microsoft 365 account.

1. **File → Add Package Dependencies…**
2. Paste this URL into the search box:
   ```
   https://github.com/AzureAD/microsoft-authentication-library-for-objc.git
   ```
3. Dependency Rule: "Up to Next Major Version", starting at `1.2.0`. Click
   **Add Package**.
4. When asked which product to add, check **MSAL** and add it to the
   `MariteConnect` target.

The project should now build (⌘B) — but sign-in will still fail until steps
5–7 below and the real Microsoft 365/Azure setup are done.

## 5. Turn on Push Notifications

1. Select the project in the navigator → select the `MariteConnect` target
   → **Signing & Capabilities** tab.
2. Click **+ Capability** → search **Push Notifications** → double-click to
   add it. Xcode creates the entitlements file for you automatically.

## 6. Add the Microsoft sign-in URL settings

Still in the target's settings, open the **Info** tab (or **Info.plist** if
your Xcode shows it as a separate file) and add:

1. **URL Types** → click **+** → set **URL Schemes** to:
   ```
   msauth.com.marite.MariteConnect
   ```
2. Add a new row with key **Queried URL Schemes** (`LSApplicationQueriesSchemes`),
   type Array, with two string items: `msauthv2` and `msauthv3`.

> These must match the app's **Bundle Identifier**. If you keep the default
> Bundle Identifier Xcode generated (something like `com.yourname.MariteConnect`),
> update it to exactly `com.marite.MariteConnect` on the **General** tab —
> or, if you'd rather keep your own bundle ID, change the URL scheme above
> and the `msalRedirectUri` line near the top of the pasted file to match it
> instead (`msauth.<your-bundle-id>://auth`).

## 7. Set your signing team (only needed to run on a real iPhone)

**Signing & Capabilities** tab → **Team** dropdown → pick your Apple ID /
Developer Team. Not needed to run in the Simulator.

## 8. Build and run

⌘R, target the iPhone Simulator. You should see the "Marite Connect" sign-in
screen. That's the whole app compiling and running — nothing more to paste.

## What still won't work yet, and why

Tapping "Sign in with Microsoft" will show an error until you:

1. Fill in the placeholder values near the top of the pasted file, inside
   `enum AppConfig` (`msalClientId`, `msalTenantId`, `staffTeamId`, `siteId`,
   `functionsBaseURL`).
2. Complete the Microsoft 365 / Entra ID / Azure / Apple setup those values
   come from — a Teams "Marite Staff" Team, an Entra ID app registration, a
   SharePoint list and document library, and a deployed backend for the
   legal assistant and push notifications.

That setup is one-time admin work, not something that can be pasted as
code — full step-by-step instructions are in `docs/SETUP.md` in the same
project:
https://github.com/jacquesdpr/Outage-Watch-/blob/claude/staff-chat-task-app-6dt2tj/MariteConnect/docs/SETUP.md

## The one part that can't live in Xcode at all

The legal assistant and push notifications need a small piece of server
code (it holds a secret key that can never be inside an app you hand out to
people) — that's a separate Node.js project, not Swift, and it doesn't get
pasted into Xcode. It runs on Microsoft Azure instead. It's already written
and sitting here, ready to deploy once you're ready for those two features:
https://github.com/jacquesdpr/Outage-Watch-/tree/claude/staff-chat-task-app-6dt2tj/MariteConnect/ServerlessBackend/marite-functions
(its own `README.md` walks through deploying it). Chat, tasks, and
SharePoint search all work without this — only the Legal Assistant tab and
"you've been tagged" push alerts need it.

## If you'd rather use the already-organized project instead

Everything in the one pasted file also exists as the same code split into
normal, separate files (the usual way an Xcode project is organized), in
this same GitHub repository, along with a project file generator so you
don't have to click through steps 1–7 above by hand. See `HANDOFF.md` in
the repo if you'd rather go that route later — it needs a Mac terminal
command or two, which is the only reason it's not the path above.
