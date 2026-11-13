# Architecture

Marite Connect runs on exactly two outside parties: **Apple** (every iPhone
app needs one anyway) and **Anthropic** (for the Legal Assistant). There is
no Microsoft 365, no Azure, no custom server, nothing to deploy or keep
running.

```
┌─────────────────────────┐
│   iPhone app (SwiftUI)   │
└─────────────┬────────────┘
              │
      ┌───────┴────────┐
      ▼                 ▼
┌───────────┐   ┌─────────────────┐
│ CloudKit   │   │ Anthropic        │
│ (Apple's   │   │ Claude API       │
│ iCloud)    │   │ (direct call)    │
│            │   └─────────────────┘
│ - Staff          ↑
│ - Channel        │ grounded by text PDFKit
│ - Message        │ extracted on-device from
│ - StaffTask      │ LegalDocument CKAssets
│ - LegalDocument ─┘
│
│ + push notifications,
│   free, via CKQuerySubscription
└───────────┘
```

## Why CloudKit instead of a backend

A shared staff chat app normally needs *something* in the middle to sync
data between phones. CloudKit's **public database** is Apple's answer to
that: every person's app reads and writes the same shared records, backed
by Apple's infrastructure, included with the same Apple Developer account
you already need to ship an iPhone app. No server to run, no hosting bill,
no separate account for staff to sign into — their existing iCloud account
(the one already on their iPhone) *is* their identity in the app.

It also solves push notifications for free: a **CKQuerySubscription**
watches for new `StaffTask` records assigned to a given person, and Apple's
own push infrastructure delivers the alert — no APNs key to generate, no
relay server to hold one. See `PushSubscriptionService.swift`.

## The tradeoff: privacy is enforced by the app, not by CloudKit

Microsoft Teams' private channels are enforced by the server — someone
outside a private channel's membership literally cannot fetch its messages
from Microsoft's infrastructure. This app's "private channels" are
different: every `Channel` and `Message` record lives in the same public
database, readable by any signed-in staff member's app. A private
channel's `isPrivate` + `memberUserRecordNames` fields just tell the app
which channels to *show* in the list and who to offer in the @mention
picker for it — someone who really wanted to could query the public
database directly (e.g. with a custom CloudKit client) and read a private
channel's messages anyway.

For a small, trusted internal team this is a reasonable tradeoff in
exchange for needing no backend at all. If a channel ever needs to keep its
contents genuinely invisible to everyone outside its membership — not just
hidden from the list — the hardening path is **CKShare**: each private
channel becomes its own shared record zone in the *private* database,
explicitly shared with specific participants, which CloudKit does enforce
server-side. That's a real rework of `ChatService`/`Channel`, not a small
patch, so it's left as a future upgrade rather than built into this
version — flag it if a channel's contents are sensitive enough to need it
(e.g. a very sensitive HR matter).

## The tradeoff: the Claude API key ships inside the app

Every other service here (Apple's CloudKit) authenticates the *person*, not
the app, so there's no secret to protect. Calling Anthropic's API is
different — it's authenticated with an API key, and with no server to hold
that key server-side, it has to live in `AppConfig.claudeAPIKey`, inside
the compiled app.

Anyone who obtained the app's binary (decompiling an `.ipa`) could in
principle extract that key and use it on your account's bill. For an app
you build yourself and hand only to Marite staff via TestFlight or MDM —
never submitted to the public App Store — this is a manageable risk:
- Set a **monthly spending limit** on the key at console.anthropic.com, so
  a leaked key costs at most that limit, not an unbounded bill.
- Rotate the key (generate a new one, update `AppConfig`, rebuild) if you
  ever suspect it's been exposed.

If this risk ever stops being acceptable — e.g. the app grows beyond a
small trusted team, or goes on the public App Store — that's the point to
add back a tiny server (even a single Cloudflare Worker or AWS Lambda) whose
only job is holding the Claude key and relaying the question, the same
shape as the Azure Function in the earlier Microsoft 365 version of this
app, minus everything else that version needed a server for.

## How a tag becomes a push notification

1. On first launch, each person picks a display name, saved as their
   `Staff` record — and a `CKQuerySubscription` is created for them,
   watching for `StaffTask` records where `assignedToUserRecordName`
   matches their own CloudKit user ID (`PushSubscriptionService`).
2. Tagging someone in the composer calls `ChatService.sendTaskMessage`,
   which saves the message, then creates a `StaffTask` record.
3. CloudKit notices the new `StaffTask` matches that person's subscription
   and has Apple's push infrastructure deliver the alert — nothing in this
   app's own code sends the push; CloudKit and the OS do it automatically
   once the iCloud + Push Notifications capabilities are in place.

This is genuinely more reliable than the earlier Microsoft 365 version's
push notifications, which were triggered by the tagging device calling a
server after the fact (and could silently fail to fire if that device lost
connectivity right after sending). Here, CloudKit's own infrastructure
reacts to the data change directly — nothing on the tagging device needs to
succeed beyond the one save that already has to succeed for the task to
exist at all.

## The Legal Library and Legal Assistant, without SharePoint

`LegalDocument` records store each PDF as a `CKAsset` — CloudKit's way of
syncing a file — so anyone can add the STSMA Act, its regulations, or a
CSOS adjudication order from their phone, and everyone's copy picks it up
automatically. When the Legal Assistant is asked a question:

1. `LegalLibraryService` extracts plain text from each PDF on-device using
   **PDFKit** (built into iOS, no library or server needed), caching it in
   memory so repeated questions don't re-parse the same file.
2. It does simple keyword scoring to find the most relevant document(s) and
   builds a short excerpt around the match.
3. `AssistantService` sends the question, a little conversation history,
   and those excerpts directly to the Claude API, and returns the answer
   with the excerpts as citations.

There's no semantic/vector search here — just keyword matching, which is
noticeably cruder than the Microsoft 365 version's Graph Search API. For a
library of a few dozen documents (the Act, regulations, a curated set of
CSOS orders) this is a reasonable tradeoff; if the library grows large
enough that keyword matching stops finding the right document, that's the
point to reconsider either a smarter on-device ranking step or bringing
back a small server to do real retrieval.
