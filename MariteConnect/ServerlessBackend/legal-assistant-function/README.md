# Legal Assistant relay (Azure Function)

The only server-side component of Marite Connect. It exists for two reasons a
shipped iOS app can't handle safely on its own:

1. Keeping the `ANTHROPIC_API_KEY` secret (never embedded in the app binary).
2. Doing full-text search + extraction over PDFs in the Sectional Title Legal
   Library, which needs server-side libraries (`pdf-parse`) and an app-only
   Graph credential separate from the signed-in user's own permissions.

Every other feature (channels, tasks, SharePoint search) talks to Microsoft
Graph directly from the app — this is the one exception.

## How a request flows

1. The iOS app POSTs `{ question, history }` to `/api/legalAssistant`, with the
   signed-in user's own Microsoft Graph access token as the `Authorization`
   bearer header.
2. The function calls `GET /me` with that token to confirm it's a real,
   current Marite staff session (`src/lib/callerIdentity.ts`). No local user
   database — Entra ID is the only identity source.
3. It acquires its own app-only Graph token (client-credentials flow, a
   *separate* Entra ID app registration — see below) and searches the legal
   library drive for documents matching the question
   (`src/lib/legalLibrary.ts`), extracting text from the top matches.
4. It sends the question, short conversation history, and the extracted
   excerpts to Claude (`src/lib/claudeClient.ts`) and returns the answer plus
   the citations used.

## One-time setup

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
3. Copy `local.settings.json.example` to `local.settings.json` and fill in:
   - `ANTHROPIC_API_KEY` — from console.anthropic.com
   - `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID`, `GRAPH_CLIENT_SECRET` — from step 1
   - `LEGAL_LIBRARY_DRIVE_ID` — from step 2
4. `npm install`
5. `npm start` (runs `func start` after building) to test locally with the
   Azure Functions Core Tools, or deploy with:
   ```
   npm run build
   func azure functionapp publish <your-function-app-name>
   ```
   Then set the same environment variables as **Application settings** on the
   deployed Function App (Azure Portal → Function App → Configuration), and
   point `AppConfig.assistantEndpoint` in the iOS app at the deployed URL.

## Extending the legal library

Drop new PDFs (the Act, regulations, individual CSOS adjudication orders)
straight into the SharePoint document library — no redeploy needed, the
function searches it live on every question. `.docx` files aren't parsed yet;
either convert them to PDF before uploading, or add a `.docx` extractor (e.g.
the `mammoth` package) alongside the PDF path in `legalLibrary.ts`.
