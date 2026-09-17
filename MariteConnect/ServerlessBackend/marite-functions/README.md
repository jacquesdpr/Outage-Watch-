# Marite Functions (Azure Function App)

The only server-side component of Marite Connect. Two things a shipped iOS
app can't safely do on its own force this:

1. Keeping secrets (`ANTHROPIC_API_KEY`, the APNs auth key) out of the app
   binary.
2. Work that needs a server: extracting text from PDFs for the legal
   assistant, and pushing to APNs (which requires holding Apple's private
   push key).

Every other feature (channels, tasks, SharePoint search) talks to Microsoft
Graph directly from the app. This Function App hosts three independent HTTP
functions that cover the exceptions:

| Function | Called when | Does |
|---|---|---|
| `legalAssistant` | Staff asks the Sectional Title Assistant a question | Searches the legal library, asks Claude, returns a cited answer |
| `registerDevice` | After sign-in / whenever iOS issues a new APNs token | Stores the device token against the user's Entra ID |
| `unregisterDevice` | On sign-out | Removes that device's token |
| `notifyTagged` | Right after a message @mentions someone (a StaffTask is created) | Pushes a "you've been tagged" alert to that person's device(s) |

All four share the same identity check
(`src/lib/callerIdentity.ts`): every request carries the calling user's own
Microsoft Graph access token as the `Authorization` bearer header, and the
function calls `GET /me` with it to confirm it's a real, current Marite
staff session before doing anything. There's no local user database —
Entra ID is the only identity source.

## Legal assistant flow

1. The iOS app POSTs `{ question, history }` to `/api/legalAssistant`.
2. After verifying the caller, the function acquires its own app-only Graph
   token (client-credentials flow, a *separate* Entra ID app registration —
   see setup below) and searches the legal library drive for documents
   matching the question (`src/lib/legalLibrary.ts`), extracting text from
   the top matches.
3. It sends the question, short conversation history, and the extracted
   excerpts to Claude (`src/lib/claudeClient.ts`) and returns the answer plus
   the citations used.

## Push notification flow

1. On sign-in, the app registers for APNs, gets a device token from iOS, and
   POSTs it to `/api/registerDevice`. The token is stored in an Azure Table
   (`DeviceTokens`, on the same storage account the Function App already
   needs — no extra database to provision) keyed by the user's Entra ID
   object ID (`src/lib/deviceTokenStore.ts`).
2. When someone tags a colleague in a channel message, the tagger's own app
   — right after creating the StaffTask via Graph — POSTs to
   `/api/notifyTagged` with who was tagged and which message/task it was.
3. The function looks up that person's device token(s) and pushes an alert
   to each via APNs (`src/lib/apnsClient.ts`), using a JWT signed with your
   APNs auth key (`.p8`). Tapping the notification deep-links into the right
   channel in the app.

This is a best-effort, client-triggered notification — not a guaranteed
delivery pipeline. If the tagger's device loses connectivity right after the
Graph call succeeds, the push simply won't fire; the task itself is never
lost (it's a normal SharePoint list row the assignee will see next time they
open the app), only the immediate alert might not arrive. A more robust
alternative is a Microsoft Graph change notification (webhook) subscription
on the StaffTasks list, so the push fires server-side the moment the row
exists regardless of the tagger's connectivity — worth adding if missed
pushes turn out to matter in practice, at the cost of maintaining a webhook
subscription that must be renewed periodically.

## One-time setup

### Legal assistant

1. **Create a second Entra ID app registration** (distinct from the app the
   iOS client uses) named e.g. "Marite Connect - Legal Library Reader". Under
   API permissions, add **Microsoft Graph → Application permissions →
   `Sites.Read.All`**, then grant admin consent. Create a client secret.
   This app registration is never used interactively — only for the
   function's own client-credentials calls.
2. Note the legal library's drive ID: in SharePoint, open the "Sectional
   Title Legal Library" document library, then call
   `GET https://graph.microsoft.com/v1.0/sites/{siteId}/drives` (e.g. via
   Graph Explorer) and copy the `id` of the matching drive.

### Push notifications

3. In [developer.apple.com](https://developer.apple.com) → **Certificates,
   Identifiers & Profiles → Keys**, create a new key with the **Apple Push
   Notifications service (APNs)** capability enabled. Download the `.p8`
   file (you can only download it once) and note its **Key ID**.
4. Note your **Team ID** (top right of the Apple Developer portal).
5. Confirm the app's bundle ID matches `APNS_BUNDLE_ID`
   (`com.marite.MariteConnect` unless you changed it in `project.yml`).

### Configure and run

6. Copy `local.settings.json.example` to `local.settings.json` and fill in:
   - `ANTHROPIC_API_KEY` — from console.anthropic.com
   - `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID`, `GRAPH_CLIENT_SECRET` — from step 1
   - `LEGAL_LIBRARY_DRIVE_ID` — from step 2
   - `APNS_KEY_ID`, `APNS_TEAM_ID` — from steps 3–4
   - `APNS_AUTH_KEY` — the full contents of the `.p8` file from step 3, with
     real newlines replaced by literal `\n` (Azure App Settings values are
     single-line)
   - `APNS_ENVIRONMENT` — `development` for a build run from Xcode /
     TestFlight-via-Xcode, `production` once distributed through TestFlight
     proper or the App Store
   - `AzureWebJobsStorage` — already defaults to the local storage emulator
     for local testing; when you deploy, the Function App's own storage
     connection string is used automatically (no change needed)
7. `npm install`
8. `npm start` (runs `func start` after building) to test locally with the
   Azure Functions Core Tools, or deploy with:
   ```
   npm run build
   func azure functionapp publish <your-function-app-name>
   ```
   Then set the same environment variables as **Application settings** on the
   deployed Function App (Azure Portal → Function App → Configuration), and
   point `AppConfig.functionsBaseURL` in the iOS app at the deployed URL.

## Extending the legal library

Drop new PDFs (the Act, regulations, individual CSOS adjudication orders)
straight into the SharePoint document library — no redeploy needed, the
function searches it live on every question. `.docx` files aren't parsed yet;
either convert them to PDF before uploading, or add a `.docx` extractor (e.g.
the `mammoth` package) alongside the PDF path in `legalLibrary.ts`.
