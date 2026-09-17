# Setup guide

Follow these in order. Steps 1–4 are one-time Microsoft 365 / Azure admin
tasks (need Global Admin or Application Administrator + SharePoint admin
rights on the Marite tenant); step 5 builds the app in Xcode.

## 1. Create the "Marite Staff" Team

This Team's channels back the app's chat feature.

1. In Microsoft Teams, create a new Team called **Marite Staff** (or reuse an
   existing one).
2. Add every staff member who should have access to the app as a member.
3. Create standard channels for anything **all staff** should see (e.g.
   `#general`, `#maintenance-requests`).
4. Create **private channels** for anything restricted to specific people
   (e.g. `#management`, `#finance`) and add only the intended members.
5. Get the Team's ID: in Teams, click **⋯** next to the Team name → **Get
   link to team**, or find it via Graph Explorer
   (`GET /me/joinedTeams`). Put it in `AppConfig.staffTeamId`
   (`Sources/MariteConnect/App/AppConfig.swift`).

## 2. Register the iOS app in Entra ID

1. Go to **Entra ID → App registrations → New registration**.
   - Name: `Marite Connect (iOS)`
   - Supported account types: **Accounts in this organizational directory
     only** (single tenant).
   - Redirect URI: platform **iOS/macOS**, value
     `msauth.com.marite.MariteConnect://auth`
     (must exactly match `AppConfig.msalRedirectUri` and the URL scheme in
     `project.yml`, and your app's actual bundle ID if you change it from
     `com.marite.MariteConnect`).
2. Under **API permissions**, add these **Delegated** Microsoft Graph
   permissions, then grant admin consent:
   - `User.Read`
   - `Team.ReadBasic.All`
   - `Channel.ReadBasic.All`
   - `ChannelMessage.Send`
   - `ChannelMessage.Read.All`
   - `Sites.ReadWrite.All`
   - `Files.ReadWrite.All`
3. Copy the **Application (client) ID** and **Directory (tenant) ID** into
   `AppConfig.msalClientId` and `AppConfig.msalTenantId`.

> Note: `Sites.ReadWrite.All` and `Files.ReadWrite.All` are broad delegated
> permissions — the user can still only actually read/write what their own
> account already has SharePoint permission for, but consider narrowing to
> specific sites with `Sites.Selected` once you've validated the app, if your
> security team prefers tighter scoping.

## 3. Create the StaffTasks SharePoint list

1. In the SharePoint site you want to host app data (can be the Team's own
   site), create a list named **StaffTasks** with these columns:

   | Column name    | Type            | Notes                        |
   |----------------|-----------------|-------------------------------|
   | Title          | Single line text | The task summary (message text) |
   | ChannelId      | Single line text | Teams channel ID |
   | ChannelName    | Single line text | For display without extra lookups |
   | MessageId      | Single line text | The Teams message being tracked |
   | AssignedToId   | Single line text | Azure AD object ID of the assignee |
   | AssignedToName | Single line text | Display name, for the UI |
   | CreatedById    | Single line text | Azure AD object ID of who tagged them |
   | CreatedByName  | Single line text | Display name |
   | Status         | Choice (`Open`, `Done`) | Default: `Open` |

2. Get the site ID: `GET https://graph.microsoft.com/v1.0/sites/{hostname}:/sites/{site-path}`
   via Graph Explorer, or `GET /sites/root` for the root site. Put it in
   `AppConfig.siteId`.
3. In the list's settings, **index the `AssignedToId` and `CreatedById`
   columns** (List Settings → Indexed columns). The app filters on them for
   "My Tasks", and SharePoint rejects `$filter` queries on large lists with
   non-indexed columns.

## 4. Create the Sectional Title Legal Library

1. In the same (or another) SharePoint site, create a document library named
   **Sectional Title Legal Library**.
2. Upload:
   - The Sectional Titles Schemes Management Act (STSMA) and its regulations
     (PDF).
   - A curated set of CSOS adjudication orders relevant to Marite's managed
     schemes (PDF). Name files descriptively (e.g.
     `CSOS Order - Trustee Dispute - Case 1234.pdf`) since the file name is
     shown as the citation title.
3. Follow `ServerlessBackend/legal-assistant-function/README.md` to register
   a second, app-only Entra ID app (`Sites.Read.All` application permission)
   and deploy the Azure Function, then set `AppConfig.assistantEndpoint` to
   the deployed Function URL.
4. Keep adding documents over time — no redeploy needed, the assistant
   searches the library live on every question.

## 5. Build the app in Xcode

Requires a Mac with Xcode 15+.

```bash
brew install xcodegen
cd MariteConnect
xcodegen generate
open MariteConnect.xcodeproj
```

In Xcode:
1. Select the `MariteConnect` target → **Signing & Capabilities** → set your
   Apple Developer **Team**, or leave automatic signing on and pick a team
   from the dropdown (also settable via `DEVELOPMENT_TEAM` in `project.yml`).
2. Confirm the values you filled into `AppConfig.swift` and the Function's
   `local.settings.json` earlier.
3. Build & run on a simulator or device signed in with a Marite Microsoft
   365 test account.
4. Replace the placeholder app icon: drag `docs/marite-logo.jpg` (the Marite
   logo) into `AppIcon` in `Assets.xcassets` in Xcode, sized to 1024×1024 for
   the App Store slot (Xcode's icon composer / an online icon generator can
   produce the full set from the one image).

### Distributing to staff

Once it builds and you've tested sign-in, chat, tasks, search, and the
assistant end to end:
- For a quick pilot: use **TestFlight** (internal testing, up to 100 users,
  no App Store review needed for internal groups).
- For company-wide rollout without the public App Store: enroll in
  **Apple Business Manager** and use its **Custom Apps** / volume purchase
  program to distribute privately to Marite-owned devices, or use **Mobile
  Device Management (MDM)** if Marite already manages staff iPhones/iPads.

## What to try first, once running

1. Sign in with a Marite Microsoft 365 account.
2. Open a standard channel, post a message, confirm it also shows up in
   Microsoft Teams itself.
3. Tag a colleague on a message (tap the **@** icon in the composer) — check
   it appears in their **My Tasks** tab, and that tapping "Mark as Done"
   clears it for both of you.
4. Search for a real document from **Search** and confirm it opens correctly
   in SharePoint/Office.
5. Ask the **Legal Assistant** a question that matches a document you
   uploaded, and confirm the citation links to the right file.
