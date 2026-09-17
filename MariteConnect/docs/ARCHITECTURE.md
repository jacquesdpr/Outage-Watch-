# Architecture

Marite Connect is a native iOS/iPadOS app (SwiftUI) that rides almost
entirely on Marite's existing Microsoft 365 tenant, plus one small serverless
function for the legal assistant. There is no custom database and no
custom chat server to run or pay for.

```
┌─────────────────────────┐
│   iPhone / iPad app      │
│   (SwiftUI, MSAL)        │
└─────────────┬────────────┘
              │ delegated Graph token (the user's own permissions)
              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Microsoft Graph API                       │
│                                                               │
│  Teams channels/messages   SharePoint list      SharePoint    │
│  (chat, @mentions)         "StaffTasks"         Search API    │
│                            (task tracking)      (file search) │
└─────────────────────────────────────────────────────────────┘
              │
              │ forwarded token, for identity only
              ▼
┌─────────────────────────┐        ┌──────────────────────────┐
│  Azure Function          │──────▶│  Anthropic Claude API      │
│  legal-assistant relay   │        │  (grounded Q&A)           │
│                          │◀──────│                            │
│  - verifies caller       │
│  - app-only Graph token  │───▶ SharePoint "Sectional Title
│    (Sites.Read.All)      │      Legal Library" (STSMA Act,
└─────────────────────────┘      regulations, CSOS orders)
```

## Why Microsoft 365 as the backend

Marite staff already have Microsoft 365 accounts, and Teams already has
exactly the two visibility models the chat feature needs:

- **Standard channels** — visible to every member of the "Marite Staff" Team.
  This is your "accessible by all staff" channel type.
- **Private channels** — visible only to the members explicitly added to
  that channel. This is your "certain people only" channel type.

Using Teams as the data store (rather than building a custom chat backend)
means: no server to run, permissions and identity managed where they already
are (Entra ID), and messages are visible in Microsoft Teams itself too if
staff prefer that client — Marite Connect is a purpose-built front end over
the same data, not a replacement inbox.

## The one non-Graph piece: the legal assistant relay

Every other feature — reading/posting channel messages, tracking tagged
tasks, and searching SharePoint — is a direct Microsoft Graph call from the
app using the signed-in user's own delegated permissions and their own
token. It genuinely needs no server.

The Sectional Title Assistant is the exception, for two unavoidable reasons:

1. It calls the Anthropic API, which requires an API key. A key embedded in
   a shipped app binary can be extracted by anyone who downloads the app —
   so the key has to live server-side.
2. Grounding answers in the actual Act/CSOS documents means extracting text
   from PDFs, which needs a server-side library, not something reasonable to
   do purely in Swift on a phone for every question.

That single Azure Function (`ServerlessBackend/legal-assistant-function`) is
intentionally as thin as possible: verify the caller is a real Marite staff
member, search the shared legal library, call Claude, return the answer with
citations. See its own README for setup.

## Task tracking model

Rather than a new task-management system, "tag someone, they must confirm"
is implemented as one extra write whenever a message @mentions someone:

1. The message is posted to the Teams channel as normal (so it's visible in
   the thread, and in Teams itself).
2. A row is added to a **StaffTasks** SharePoint list: who was tagged, by
   whom, in which channel/message, and a status of `Open`.
3. The tagged person sees a "Mark as Done" affordance both inline under the
   message and in the **My Tasks** tab (which is just a filtered view of
   that list). Tapping it flips the row to `Done`.

This keeps "did anyone confirm this" queryable and impossible to lose in
scroll-back, without inventing a parallel task/project-management product.

See `docs/SETUP.md` for the exact list schema.
