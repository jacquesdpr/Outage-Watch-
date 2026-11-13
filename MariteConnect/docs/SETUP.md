# Setup guide

Everything here is one-time setup. Unlike the earlier Microsoft 365 version
of this app, there's no tenant admin to coordinate with — the two things you
need are an Apple Developer account (to ship an app to your own iPhone at
all) and an Anthropic API key (for the Legal Assistant).

## 1. Apple Developer account

If you don't already have one: enroll at developer.apple.com ($99/year, or
free for just running on your own device via Xcode without distributing to
others — see "Distributing to staff" below for the difference).

## 2. Create the CloudKit container

1. In Xcode (after you've created the project — see HANDOFF.md or
   PASTE_IN_XCODE.md): select the target → **Signing & Capabilities** → **+
   Capability** → add **iCloud**. Check **CloudKit** under services.
2. Xcode offers to create a container for you, named after your bundle ID
   by default (`iCloud.com.marite.MariteConnect` if you kept the bundle ID
   from this project). Confirm it matches `AppConfig.cloudKitContainerIdentifier`
   and the entitlements file.
3. Add the **Push Notifications** capability too (same screen, **+ Capability**).

## 3. Create the CloudKit schema

Open the [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/),
pick your container, switch to the **Development** environment, and create
these record types under **Schema → Record Types**. For each, add the
fields listed, then mark the ones noted "queryable"/"sortable" as such under
**Indexes** (CloudKit rejects queries that filter or sort on a field with no
matching index).

### Staff
| Field | Type | Index |
|---|---|---|
| userRecordName | String | Queryable |
| displayName | String | Queryable, Sortable |

### Channel
| Field | Type | Index |
|---|---|---|
| name | String | Queryable, Sortable |
| channelDescription | String | — |
| isPrivate | Int(64) | — |
| memberUserRecordNames | String List | — |
| createdByUserRecordName | String | — |
| createdByName | String | — |

### Message
| Field | Type | Index |
|---|---|---|
| channel | Reference | Queryable |
| senderUserRecordName | String | — |
| senderName | String | — |
| text | String | — |
| taggedUserRecordName | String | — |
| taggedUserName | String | — |

Also mark the built-in **Creation Date** metadata field as **Sortable** on
Message (used to show messages in order).

### StaffTask
| Field | Type | Index |
|---|---|---|
| channelRecordName | String | Queryable |
| channelName | String | — |
| messageRecordName | String | — |
| summary | String | — |
| assignedToUserRecordName | String | Queryable |
| assignedToName | String | — |
| createdByUserRecordName | String | Queryable |
| createdByName | String | — |
| status | String | Queryable |

### LegalDocument
| Field | Type | Index |
|---|---|---|
| title | String | Queryable, Sortable |
| file | Asset | — |
| uploadedByName | String | — |

### Security Roles

By default, CloudKit's public database lets any signed-in iCloud user read
and write. That's the right call here — this app has no separate login, so
"signed into iCloud" is the only identity check there is (see
docs/ARCHITECTURE.md for the tradeoff that comes with that). Leave the
default **World** role as **Read/Write** for all five record types; you
don't need to touch Security Roles for this app to work.

### Deploy the schema to Production

Everything above happens in CloudKit's **Development** environment by
default — fine while you're building. Before handing the app to staff
(TestFlight or otherwise), go to **Deploy Schema Changes** in the Dashboard
and push it to **Production**, since release builds use the production
environment automatically.

## 4. Get a Claude API key

1. Go to [console.anthropic.com](https://console.anthropic.com) → **API
   Keys** → create one.
2. **Set a monthly spending limit** on it (Settings → Limits) — since this
   key ships inside the app binary, capping it bounds the worst case if
   it's ever extracted from a build you hand out.
3. Put it in `AppConfig.claudeAPIKey`.

## 5. Build and run

See **HANDOFF.md** (organized multi-file project, needs a Mac terminal
command) or **PASTE_IN_XCODE.md** (one file, all clicking, no terminal) —
whichever you'd rather do.

## What to try first, once running

1. Launch on your iPhone, signed into your own iCloud account. Pick a
   display name when asked.
2. Create a channel (tap **+** in Channels). Try one standard, one private
   (pick members from the staff list — empty until a second person has
   opened the app and picked a name).
3. Post a message, then tag someone (tap the **@** icon) — check it shows up
   in their **My Tasks**, and that a push notification arrives on their
   phone when they're not in the app.
4. Add a PDF to the **Library** tab (the STSMA Act or a CSOS order) and
   confirm it opens when tapped.
5. Ask the **Legal Assistant** a question that should match that PDF, and
   check its answer cites it.

## Distributing to more than your own phone

Running on your own iPhone from Xcode needs nothing beyond a free Apple ID.
To get it onto other staff's phones:
- **TestFlight** (needs the paid $99/year Developer account): internal
  testing, up to 100 people, no App Store review for an internal group.
- **Apple Business Manager + Custom Apps**, or your own **MDM**, if Marite
  already manages staff phones: distribute privately without TestFlight or
  the public App Store at all.

Either way, each person's iPhone needs to be signed into **its own normal
iCloud account** (not a shared one) — that's what CloudKit uses to tell
staff apart, the same as any other iCloud-backed app.
