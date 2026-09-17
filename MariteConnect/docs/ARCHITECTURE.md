# Architecture

Marite Connect is a native iOS/iPadOS app (SwiftUI) that rides almost
entirely on Marite's existing Microsoft 365 tenant, plus one small serverless
Function App for the legal assistant and push notifications. There is no
custom database and no custom chat server to run or pay for.

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
┌────────────────────────────────┐        ┌──────────────────────────┐
│  Azure Function App             │──────▶│  Anthropic Claude API      │
│  (marite-functions)             │        │  (grounded Q&A)           │
│                                  │◀──────│                            │
│  - verifies caller (GET /me)    │
│  - legalAssistant: app-only     │───▶ SharePoint "Sectional Title
│    Graph token, Sites.Read.All  │      Legal Library" (STSMA Act,
│                                  │      regulations, CSOS orders)
│  - registerDevice /             │
│    unregisterDevice: stores     │───▶ Azure Table "DeviceTokens"
│    APNs token per Entra ID user │
│  - notifyTagged: looks up the   │
│    tagged user's device tokens  │───▶ Apple Push Notification
│    and pushes an alert          │      service (APNs)
└────────────────────────────────┘
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

## The two non-Graph pieces: the Function App

Every other feature — reading/posting channel messages, tracking tagged
tasks, and searching SharePoint — is a direct Microsoft Graph call from the
app using the signed-in user's own delegated permissions and their own
token. It genuinely needs no server. Two things do, both hosted in the same
Azure Function App (`ServerlessBackend/marite-functions`), kept as thin as
possible: verify the caller is a real Marite staff member (`GET /me` with
their own forwarded token), do the one piece of work that needs a server,
return the result. See its own README for setup.

**The Sectional Title Assistant**, for two unavoidable reasons:

1. It calls the Anthropic API, which requires an API key. A key embedded in
   a shipped app binary can be extracted by anyone who downloads the app —
   so the key has to live server-side.
2. Grounding answers in the actual Act/CSOS documents means extracting text
   from PDFs, which needs a server-side library, not something reasonable to
   do purely in Swift on a phone for every question.

**Push notifications**, for one unavoidable reason: sending an APNs push
requires holding Apple's private push key (a `.p8` file), which — like the
Anthropic key — can never live in a shipped app binary. The Function App
also keeps the registry of whose device has which APNs token (an Azure
Table, `DeviceTokens`, on the same storage account the Function App already
needs — not a separate database). See "Push notifications" below for how a
tag turns into an alert.

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

## Push notifications

1. On sign-in, the app requests notification permission and registers for
   APNs; once iOS hands it a device token, it's sent to
   `/api/registerDevice` (and removed via `/api/unregisterDevice` on sign
   out) so the backend knows which device belongs to which Entra ID user.
2. When someone tags a colleague (Step 2 of "Task tracking model" above),
   the tagger's own app calls `/api/notifyTagged` right after the StaffTask
   is created, naming who was tagged and which message/task it was.
3. The Function looks up that person's registered device(s) and pushes an
   alert via APNs. Tapping it opens the app straight to that channel
   (`Push/DeepLinkRouter.swift` on the iOS side).

This is intentionally the client that just sent the tag telling the backend
to notify someone, not a background job watching for changes — it's the
simplest thing that gets an alert onto a phone within a second or two of
being tagged, and the task itself is never at risk of being lost even if the
push doesn't arrive, since it's a normal SharePoint list row. A Microsoft
Graph change-notification (webhook) subscription on the StaffTasks list
would fire server-side regardless of the tagger's connectivity — a more
robust alternative worth adding if missed pushes turn out to matter, at the
cost of maintaining a subscription that needs periodic renewal.
