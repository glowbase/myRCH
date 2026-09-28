# myRCH

An iPhone app for families using **My RCH Portal**, the Royal Children's Hospital Melbourne's Epic MyChart patient portal. It shows a child's appointments, test results, medications, health summary and growth in a native, parent-friendly interface, and adds features the portal doesn't have, such as medication reminders.

> [!CAUTION]
> **This is an unofficial, independent project. The Royal Children's Hospital Melbourne (RCH) has not authorised, endorsed or reviewed it, and hasn't given permission for it.** It isn't affiliated with RCH or with Epic Systems Corporation. See the full [Disclaimer](#disclaimer) before using it.

## Disclaimer

**Not authorised by RCH.** This app is built and maintained by a parent, independently of the Royal Children's Hospital Melbourne. RCH hasn't given permission for it and hasn't approved, endorsed, reviewed or tested it. Nothing in this project should be read as suggesting otherwise.

**No support from RCH or Epic.** Please don't contact RCH, its staff or Epic for help with this app. For anything about your child's care or your portal account, use the official [My RCH Portal](https://myrchportal.rch.org.au/MyRCHPortal/) or contact the hospital directly.

**Unofficial API.** In live mode the app talks to the portal's **private web API**: the same endpoints the website calls from its own JavaScript. They were worked out by observing the website's traffic from the author's own account. Epic doesn't publish or support this API. It can change or stop working at any time without notice, and automated use of it **may breach the portal's terms of use**. You are responsible for checking whether your use is allowed. The supported route for third-party apps is SMART on FHIR (see [Roadmap](#roadmap)).

**Personal use with your own account only.** Use it only with a portal account you're entitled to use, such as your own or your child's through proxy access. Don't use it to access anyone else's records, and don't use it to put load on the portal.

**Not a medical device, and not medical advice.** Information is shown as the portal provides it, and may be incomplete, out of date or displayed wrongly: for example, a value in the wrong range, a missing result, or a reminder that doesn't fire. Always check important information against the official portal, and follow your care team's advice. **Don't rely on this app's medication reminders as your only reminder.** In an emergency, call 000.

**Trademarks.** "The Royal Children's Hospital", "RCH", "My RCH Portal", the RCH logo and related names and marks belong to the Royal Children's Hospital Melbourne. "Epic" and "MyChart" are trademarks of Epic Systems Corporation. They're used here only to describe what the app works with, and are **not covered by this project's licence** (see [Licence](#licence)).

**No warranty.** The software is provided "as is", without warranty of any kind, as set out in the [licence](LICENSE). Use it at your own risk.

## Contents

- [Disclaimer](#disclaimer)
- [Features](#features)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Project structure](#project-structure)
- [Privacy and security](#privacy-and-security)
- [Portal API reference](#portal-api-reference)
- [Mapping a new endpoint](#mapping-a-new-endpoint)
- [Roadmap](#roadmap)
- [Licence](#licence)

## Features

**Home** (styled after the Health app's Summary)
- The child's first name, age and **UR number**. Tap the UR number for a large-print sheet at full brightness, like a Wallet pass.
- Diagnosis and allergy pills linking to the health summary
- **Pinned sections** you can reorder or hide with **Edit Home**: Highlights, Upcoming Visits, Recent Results (with trend sparklines), Medication, Immunisations, Health Goals, Share My Record and Explore More
- **Highlights**: plain-language notes worked out on the device, such as the next visit, doses still to log, new or flagged results and unread messages
- **Explore More** cards from the hospital, which can be dismissed and restored
- Pull to refresh

**Browse**
- Every section as a Health-style tile grid
- Search that finds sections and individual records: results, letters, medication, visits, immunisations

**Medical ID**
- Name, date of birth, UR number, allergies, conditions and current medication on one page, at full brightness for triage

**Widgets, controls and Live Activities**
- **Next Dose:** Taken and Skip buttons that log straight from the Home Screen. Also a one-line Lock Screen version ("Hypersal · 8:00 pm") and a Lock Screen card.
- **Medication:** today's progress, including a Lock Screen ring and a large ring for StandBy.
- **Next Visit**
- **UR Number:** large, for check-in. Tap it for the Medical ID at full brightness.
- **Allergy Alert:** opt-in in Settings, because it's readable without unlocking.
- **What's New:** new results and unread messages, as of the last time the app was opened.
- **Choosing a child:** each widget can be set to a child in Edit Widget.
- **Control Centre:** **Show UR Number** and **Log Next Dose**.
- **Live Activities:**
  - a dose that's due, with Taken and Skip, on the Lock Screen and in the Dynamic Island
  - the day of a visit: a countdown and where to check in
- **How it works:**
  - The app shares a per-child snapshot through an App Group. It's republished whenever a dose changes, from anywhere, including the other parent's phone.
  - Widget and Live Activity buttons are App Intents that run in the app (`LiveActivityIntent` with `allowedExecutionTargets = .main`). If they can't run there, taps are queued and applied when the app next opens.
  - iOS only lets an app start a Live Activity while it's open, so activities appear when myRCH is next opened. Updating and ending them works any time.
  - Most content is hidden on the Lock Screen until the phone is unlocked. The snapshot is deleted on sign-out.

**Test results**
- Results grouped by month, with search and filters (type, unread, outside normal range)
- A **within / outside normal range** pill on each result, loaded as rows scroll into view
- Per-test icons: microbe for cultures, blood drop for blood counts, lungs for chest imaging, and more
- Result detail:
  - each value with a **range graph**, including one-sided ranges such as `<5` or `>200`, and qualified values such as `>500`
  - **trends**: each value's history across earlier results of the same test, with 6M / Y / All ranges and the normal range shaded
  - **culture results** listed per organism, with a colour-scaled colony-count meter
  - **imaging reports** as text, in a monospaced font like the portal's
  - clinician comments, and attached scans (PDF or image viewer)
  - specimen, status, result date and resulting lab

**Medications**
- Current and past medications, with names tidied up ("Salbutamol 100 microgram/actuation Inhaler") and icons by form (tablet, liquid, inhaled…)
- Detail page with an **AKA** banner for brand names, instructions, prescription details, and whether repeats are available
- **Reminders modelled on the Health app's:**
  - a notification at each dose time, with **Mark as Taken**, **Skip** and **Remind Me in 10 Minutes** actions
  - a **follow-up after 30 minutes** if the dose isn't logged
  - a log of today's doses in the app
- **Personal notes** per medication
- **Shared reminders:** invite another parent through iCloud, from Medication or Settings. They get the same reminders, and doses and notes either of you log show on both phones (see *Sharing reminders between parents* below).

**Also**
- Appointments with preparation steps and visit summaries
- Health summary: health issues, allergies and immunisations
- Growth charts against WHO/CDC reference percentiles
- Messages with the care team: Inbox, Bookmarked and Archived; bookmark, read/unread and archive (also in bulk); replies with photo and file attachments
- Letters from the hospital (clinic letters, referrals, absence letters), by month, with a type filter and search
- Proxy access: switch between children linked to one parent account
- Sign in with the portal's two-step verification code, and optionally remember the device

## Requirements

| Item | Version / note |
|---|---|
| Xcode | With the iOS 27 SDK |
| iOS deployment target | 27.0 |
| Swift | 5 language mode |
| Apple Developer Program | **Paid membership required** for the *Time Sensitive Notifications* capability, which lets reminders break through Focus modes. A free team can't sign the app with this capability; see below. |
| App Groups | `group.com.cooperbeltrami.myRCH`, shared by the app and widgets. Change it in both targets' entitlements and in `WidgetSnapshot.swift` (two copies) if you use your own bundle ID. |
| Portal account | A My RCH Portal login, only for live mode. Demo mode needs none. |

## Getting started

1. Clone the repo and open `myRCH.xcodeproj`.
2. In **Signing & Capabilities**, choose your **Team** and set a real **Bundle Identifier** (e.g. `au.yourname.myrch`). The placeholder `devplaceholder.…` ID can only use a wildcard profile, which can't carry the Time Sensitive capability.
   - No paid membership? Remove the Time Sensitive capability and change `content.interruptionLevel` in `MedicationStore.swift` to `.active`. Reminders still work, but a Focus mode will silence them.
3. Build and run on a device or simulator.
4. On the sign-in screen, choose the mode:
   - **Demo mode (default):** runs entirely on local sample data from `MockPortalService`, with no network access.
   - **Live portal:** turn on the live toggle and sign in with your My RCH Portal username and password. The first sign-in asks for a verification code sent by SMS or email; choose "remember this device" to skip it next time.

## Project structure

```
myRCH/
├── MyApp.swift                    App entry; injects Session and MedicationStore
├── Models/PortalModels.swift      Value types: TestResult, Medication, Appointment…
├── Services/
│   ├── PortalService.swift        Protocol every backend implements
│   ├── MockPortalService.swift    Demo data
│   ├── MyChartWebService.swift    Live portal client (actor); see API reference
│   ├── EpicFHIRService.swift      SMART on FHIR skeleton (not yet implemented)
│   ├── Session.swift              Sign-in state, active child, backend selection
│   └── MedicationStore.swift      Notes, reminders and dose log (on-device)
├── Support/                       Theme, formatting, Keychain, growth references
└── Views/                         SwiftUI screens, one file per feature
myRCHWidgets/                      Widget extension (Next Visit, Medication)
Tools/
└── probe_portal_request.py        Finds which headers a portal request needs
```

Views depend only on the `PortalService` protocol, so the demo, live and future FHIR backends are interchangeable. `Session.service` picks the backend.

## Sharing reminders between parents

Reminders, the dose log and medication notes have no portal API, so they live on the device. They can also be shared with another parent through **CloudKit sharing**. This works between different Apple IDs, and each parent uses their own My RCH Portal login.

- **One zone per child.** The zone is named from a hash of the child's UR number, which is the same in every parent's login. The portal's own patient and medication ids differ between logins, so they can't be used to match.
- **Matching medications.** A medication is matched by a hash of its name, and this phone remembers which local medication each one corresponds to. Shared data for a medication this phone hasn't loaded yet is held until it does.
- **Records:**
  - `Schedule`: a medication's dose times
  - `Dose`: one per logged scheduled or as-needed dose
  - `Note`: one per note

  Medicine and child names, times and note text are stored in `encryptedValues`.
- **Owner and participant.** Whoever shares first owns the zone, in their private database, with a zone-wide `CKShare`. The invited parent sees it in their shared database. Two `CKSyncEngine`s (private and shared) handle fetch, send, retry and push. When both change the same record, the most recent change wins.
- **Reminders.** Each phone schedules its own reminders from the shared times. Changes arrive by silent push or when the app opens, so a follow-up can occasionally still fire for a dose the other parent has just logged.
- **Setup.** Sharing needs the iCloud (CloudKit, container `iCloud.com.cooperbeltrami.myRCH`) and Push Notifications capabilities, `CKSharingSupported` in Info.plist, and the remote-notification background mode.
  - Builds from Xcode use the CloudKit **development** environment. Both phones need a development build to share with each other.
  - Deploy the schema to production in CloudKit Console before TestFlight or App Store builds.

## Privacy and security

- **Credentials** are stored in the iOS Keychain and sent only to `myrchportal.rch.org.au` over HTTPS. The password is never logged.
- **Network:** the live client uses an *ephemeral* `URLSession`, so cookies stay in memory and nothing is written to the on-disk URL cache.
- **Debug logging** prints status codes, cookie *names*, and response *shapes* (keys, types and booleans), never values, tokens or health data.
- **Notes, reminder times and dose logs** stay on the device, in Application Support with file protection. They're never sent to the portal.
- **Notifications** show the child's first name and the medicine, e.g. "Time for Sam's Ventolin", which can be visible on the lock screen. To hide it, turn off previews for the app in iOS Settings.
- **Captures:** when capturing requests to map new endpoints, remove the `Cookie:` and `__RequestVerificationToken:` headers before sharing them anywhere. They're live session credentials.

## Portal API reference

Worked out from the MyRCHPortal website's own traffic, as of September 2026. All paths are relative to the base URL. Values in `<angle brackets>` are placeholders.

```
https://myrchportal.rch.org.au/MyRCHPortal/
```

### Conventions

**Two families of endpoint.**

| Family | Example | Request | Response |
|---|---|---|---|
| `api/…` (React app) | `api/test-results/GetList` | `POST`, JSON body | JSON |
| Legacy MVC | `Visits/VisitsList/LoadUpcoming` | `POST`, parameters in the query string, optional form-encoded body | JSON |

**Headers for `api/` calls**

| Header | Value |
|---|---|
| `Content-Type` / `Accept` | `application/json` |
| `Origin` | `https://myrchportal.rch.org.au` |
| `Referer` | An `app/…` page, e.g. `…/MyRCHPortal/app/health-summary` |
| `__RequestVerificationToken` | The signed-in anti-forgery token (see [Authentication](#authentication)) |

Legacy MVC calls instead send `X-Requested-With: XMLHttpRequest`, a jQuery-style `Accept`, and a `noCache=<random>` query parameter, as the site's own calls do.

**Cookies.** The session is carried in cookies set during sign-in: `_Host-MyChart_Session`, the auth-ticket and session-token cookies, and a `_Host-MyChartAccessToken…` JWT. The JWT is issued when an `app/…` page loads, so the client loads `app/health-summary` once after signing in.

**Patient context.** Data endpoints return data for whichever patient the session is currently switched to (see [Proxy context](#proxy-context)). Calling one in the wrong context usually gives **HTTP 500 with an empty body**.

**Session expiry.** An expired session typically returns **HTTP 200 with the login page's HTML** rather than an error, so check for HTML or `Authentication/Login` in the body.

**IDs.** Record IDs look like `WP-24…-3D`. They're opaque, encrypted keys, and the ones seen so far stay the same across sessions. In the result list they appear as dictionary keys with a trailing `^`, e.g. `"<key>^"`.

**Dates** come in several formats, sometimes several in one response:

| Field style | Example | Notes |
|---|---|---|
| `…InstantISO` | `2026-03-03T09:15:00+11:00` | ISO 8601 with offset |
| `latestUpdateInstantISO` | `2026-03-03T09:15:00` | **No time zone**; avoid |
| `…Display` / `…TimestampDisplay` | `03 Mar, 2026 9:15 AM` | Hospital local time (Melbourne) |
| `formattedDateNoted` | `14/01/2026` | `dd/MM/yyyy` |
| Medication dates | `3 March, 2026` | `d MMMM, yyyy` |

### Endpoint summary

"Verified" means checked against real responses and fully decoded by the app. "Unverified" means the app calls a guessed endpoint name and doesn't yet decode the response.

| Area | Method and path | Status |
|---|---|---|
| Sign in | `GET Authentication/Login`, `POST Authentication/Login/DoLogin` | Verified |
| Two-step code | `POST Authentication/SecondaryValidation/SendCode`, `…/Validate` | Verified |
| Device | `POST Authentication/RememberDevices/ReconcileWebDevice` | Verified |
| CSRF token | `GET Home`, `GET app/health-summary`, fallback `GET Home/CSRFToken` | Verified |
| Proxy context | `GET ProxySwitch`, `GET <LinkUrl>` | Verified |
| MRN | `GET Home` (print header) | Verified |
| Visits | `POST Visits/VisitsList/LoadUpcoming`, `…/LoadPast` | Working; past-visit layout partly mapped |
| Visit notes | `POST api/visit-notes/GetVisitNotes` | Verified |
| Visit notes and After Visit Summary content | `POST api/report-content/LoadReportContent` | Verified |
| Past-visit details (After Visit Summary IDs) | `POST api/visits/past-details/GetVisitDetailsPast` | Verified |
| Test results list | `POST api/test-results/GetList` | Verified |
| Test result details | `POST api/test-results/GetDetails` | Verified |
| Imaging report | `POST api/report-content/LoadReportContent` | Verified |
| Scans | `GET Clinical/TestResults/BlobScans/BlobScansDownloadOrStream` | Link format verified; file type not yet confirmed |
| Medications | `POST api/medications/LoadMedicationsPage` | Verified |
| Health issues | `POST api/HealthIssues/LoadHealthIssuesData` | Verified |
| Messages list | `POST api/conversations/GetConversationList` | Verified |
| Conversation | `POST api/conversations/GetConversationDetails` | Verified |
| Reply | `POST api/conversations/GetComposeId`, `SaveReplyDraft`, `SendReply`, `RemoveComposeId`, `DeleteReplyDraft` | Verified (multi-line format unconfirmed) |
| Attachment upload | `POST DocumentUpload/UploadFile` (multipart) | Verified |
| Explore More | `POST ExploreMoreFeed` | Verified |
| Health goal | `POST api/goals/LoadPatientGoals`, `SavePatientGoal` | Verified (single goal) |
| Bulk unread / remove bookmark / trash | `POST api/conversations/BulkConversationAction` | Verified |
| Bookmark / Trash / Restore | `POST api/conversations/Bookmark`, `RemoveBookmark`, `MoveToTrash`, `RestoreFromTrash` | Verified |
| Reply, new message, archive, bookmark | Unknown | Not yet captured |
| Care team | `POST api/conversations/GetRecipients` | Unverified |
| Growth charts | `POST api/growth-charts/GetGrowthCharts` | Verified |
| Allergies | `POST api/allergies/LoadAllergies` | Unverified |
| Immunisations | `POST api/immunizations/LoadImmunizations` | Verified |
| Immunisation details | `POST api/immunization-details/GetImmunizationDetails` | Verified |
| Letters list | `POST api/letters/GetLettersList` | Verified |
| Letter | `POST api/letters/GetLetterDetails` | Verified |

### Authentication

**1. Load the login page:** `GET Authentication/Login`

Read the hidden inputs of the `<form id="actualLogin">` form, including `__RequestVerificationToken`. The visible form posts nowhere; the page's script submits `actualLogin` instead.

**2. Sign in:** `POST Authentication/Login/DoLogin`, form-encoded, with the hidden fields from step 1 plus:

| Field | Value |
|---|---|
| `LoginInfo` | JSON: `{"Type":"StandardLogin","Credentials":{"LoginIdentifier":"<base64 username>","Password":"<base64 password>"}}`. Each value is Base64 of the UTF-8 string. |
| `DeviceId` | The remembered device ID, if any. Skips the two-step code. |

The response redirects. Work out the outcome from the final URL and page:

| Final page | Meaning |
|---|---|
| Still contains `id="loginForm"` | Wrong username or password |
| `…/Home/Error?code=<n>` | Rejected before the credentials were checked |
| `…/Authentication/SecondaryValidation` | A two-step code is needed (step 3) |
| Anything else | Signed in (step 4) |

**3. Two-step verification.** The SecondaryValidation page's inline script holds `Workflow`, `IsPostLogin2FA`, `RememberMeSettings.Enabled` and `EnrollDeviceTracking`.

- **Send a code:** `POST Authentication/SecondaryValidation/SendCode`, form-encoded:
  ```
  deliveryMethodSMS=true      (or deliveryMethodEmail=true)
  resendCode=false
  workflow=<Workflow>
  ```
  Returns `{"Success": true}`.
- **Check the code:** `POST Authentication/SecondaryValidation/Validate`, form-encoded:
  ```
  TwoFactorCode=<code>
  RememberMe=checked          (or empty)
  IsPostLogin2FA=<true|false>
  EnrollDeviceTrackingOnRemember=<RememberMe enabled && EnrollDeviceTracking>
  DeviceId=<remembered id or empty>
  Workflow=<Workflow>
  isTOTP=false
  ```
  Returns `{"Success": true, "RememberDeviceId": "<id>"}`, or `Success: false` with `TwoFactorCodeFailReason` (`"codeexpiredtf"` means the code expired). Store `RememberDeviceId` and send it as `DeviceId` on later sign-ins.

Both calls send the token from step 1 as the `__RequestVerificationToken` header.

**4. Finish signing in.**
- `GET Home` embeds the signed-in token in `<div id="__CSRFContainer"><input name="__RequestVerificationToken" value="…">`. The pre-login token stops working after sign-in. Fallback: `GET Home/CSRFToken`, which returns a bare `<input>` whose value is the token.
- `POST Authentication/RememberDevices/ReconcileWebDevice`, form-encoded `deviceId=<id or empty>&skipSessionCheck=false`, returns `{"deviceId": "<id>", "forceUpdate": <bool>}`. Keep the issued ID if none is stored or `forceUpdate` is true.
- `GET app/health-summary` issues the `_Host-MyChartAccessToken…` cookie, and its `__CSRFContainer` token is the one `api/` calls accept. Use that page as the `Referer`.

### Proxy context

**List accounts:** `GET ProxySwitch` (`Accept: application/json`)

```json
{
  "ProxySubjectList": [
    { "Id": "", "DisplayName": "<parent>", "IsSelf": true,  "IsSelected": false, "LinkUrl": "…" },
    { "Id": "<id>", "DisplayName": "<child>", "IsSelf": false, "IsSelected": true,  "LinkUrl": "inside.asp?mode=proxyswitch&action=switchcontext&eid=<eid>" }
  ]
}
```

**Switch:** `GET <LinkUrl>`. It's relative to the base URL. Switch before calling any data endpoint for that patient, and don't run two switches at once.

### MRN

`GET Home`. The page has a print-only header:

```html
<div class="printheader">Name: <name> | DOB: <d/m/yyyy> | MRN: <digits> | PCP: <practice> | Legal Name: <name></div>
```

The app reads only the `MRN:` field, for the patient in the current context.

### Visits (legacy MVC)

**Upcoming:** `POST Visits/VisitsList/LoadUpcoming?timeZone=<IANA zone>&ComponentNumber=5&noCache=<random>`

**Past:** `POST Visits/VisitsList/LoadPast?loadpast=1&searchString=&oldestRenderedDate=<ISO 8601>&ComponentNumber=7&noCache=<random>`, form body `serializedIndex=`

`Referer: …/MyRCHPortal/Visits`. Upcoming visits are split across `InProgressVisits`, `NextNDaysVisits` and `LaterVisitsList`; past visits sit somewhere under `List`, so the app collects every object that looks like a visit. Fields used:

| Field | Meaning |
|---|---|
| `Csn` / `Id` | Visit identifier |
| `VisitTypeName` | e.g. "Clinic visit" |
| `PrimaryProviderName`, `PrimaryProvider` | Clinician |
| `PrimaryDepartment` | Department, including `Address` (an array of lines) |
| `DurationInMinutes` | Length |
| `TelehealthMode`, `CanShowTelemedicine`, `IsUnverifiedOnDemandVideoVisit` | Telehealth |
| `IsCanceled`, `IsNoShow`, `LeftWithoutSeen` | Outcome |
| `IsVisitSummaryEnabled`, `HasDownloadSummaryLink` | After-visit summary |

### Test results list

`POST api/test-results/GetList`, `Referer: …/app/test-results`

```json
{
  "groupType": "UNINITIALIZED",
  "searchString": "",
  "maxResults": 0,
  "isCurAdmFilterEnabled": false,
  "startDate": "",
  "endDate": "",
  "orgFeatureFlags": {
    "<organization-id>": { "hasGrouping": false, "hasDateRangeFilterProperties": true }
  }
}
```

`maxResults: 0` means no limit. `<organization-id>` is the hospital's organisation key; the site always sends it, and the app sends the same value.

**Response**

```json
{
  "areResultsFullyLoaded": true,
  "groupBy": "ORDER",
  "newResultGroups": [
    { "key": "<key>", "resultList": ["<key>"], "sortDate": "<ISO>", "formattedDate": "03 Mar, 2026",
      "contactType": "Clinic/Practice Visit", "organizationID": "<org>", "visitProviderID": "<id>",
      "isInpatient": false, "isEDVisit": false }
  ],
  "newResults": {
    "<key>^": {
      "name": "FULL BLOOD COUNT",
      "key": "<key>",
      "orderMetadata": {
        "orderProviderName": "",
        "authorizingProviderName": "<clinician>",
        "prioritizedInstantISO": "<ISO>",
        "resultType": "LAB",
        "read": "Read"
      },
      "resultComponents": [],
      "hasAllDetails": false,
      "isAbnormal": false,
      "hasComment": false,
      "providerComments": [ { "content": { "wmgId": "<id>", "isUnread": false } } ]
    }
  },
  "newProviderPhotoInfo": { "<provider-id>^": { "name": "<clinician>", "photoUrl": "" } },
  "newComments": { "<wmgId>^": { "content": { "deliveryInstantISO": "<ISO>" }, "author": { "name": "<clinician>" } } }
}
```

Notes:
- `newResults` is a **dictionary**, so its order isn't meaningful. Sort by `prioritizedInstantISO`, and break ties explicitly, since many results from one blood draw share a timestamp.
- Names are upper case. `resultType` values seen so far are `LAB` and `IMAGING`.
- The list response has **no values or ranges** (`hasAllDetails: false`). Use GetDetails for those.

### Test result details

`POST api/test-results/GetDetails`

```json
{ "organizationID": "", "orderKey": "<result key>", "PageNonce": "<32 hex characters>" }
```

The site generates a new `PageNonce` for each page load. Any value is accepted.

**Response** (abridged)

```json
{
  "orderName": "…",
  "key": "<key>",
  "results": [
    {
      "name": "…",
      "isAbnormal": false,
      "hasAllDetails": true,
      "orderMetadata": {
        "resultStatus": "Final",
        "specimensDisplay": "Blood (Venous)",
        "resultTimestampDisplay": "03 Mar, 2026 9:15 AM",
        "collectionTimestampsDisplay": "…",
        "latestUpdateInstantISO": "2026-03-03T09:15:00",
        "readingProviderName": "",
        "resultingLab": { "name": "…", "address": ["…"], "phoneNumber": "…", "labDirector": "…" }
      },
      "resultComponents": [
        {
          "componentInfo": { "componentID": "<id>", "name": "C-Reactive Protein", "commonName": "…", "units": "mg/L" },
          "componentResultInfo": {
            "value": "<1",
            "abnormalFlagCategoryValue": "Unknown",
            "referenceRange": {
              "displayLow": "", "displayHigh": "",
              "formattedReferenceRange": "<5",
              "lowerBoundExclusive": false, "upperBoundExclusive": false
            }
          },
          "componentComments": { "hasContent": false, "contentAsString": "", "contentAsHtml": "" }
        }
      ],
      "studyResult": {
        "narrative":  { "hasContent": false, "contentAsString": "", "contentAsHtml": "" },
        "impression": { "hasContent": false, "contentAsString": "", "contentAsHtml": "" },
        "combinedRTFNarrativeImpression": { "hasContent": false },
        "addenda": [], "hasStudyContent": false
      },
      "resultNote":   { "hasContent": false },
      "resultLetter": { "hasContent": false },
      "reportDetails": {
        "isDownloadablePDFReport": false,
        "reportID": "<id or empty>",
        "reportVars": { "ordId": "<id>", "ordDat": "<id>" }
      },
      "imageStudies": [ { "downloadUrl": "/Clinical/TestResults/BlobScans/BlobScansDownloadOrStream?…", "isMobile": false } ],
      "scans": [],
      "providerComments": [
        { "content": { "wmgId": "<id>", "body": "<comment text>", "deliveryInstantISO": "<ISO>" },
          "author": { "name": "<clinician>", "providerId": "<id>" } }
      ]
    }
  ]
}
```

Quirks:
- **`abnormalFlagCategoryValue` is `"Unknown"` for in-range values.** Don't treat every non-empty flag as abnormal. Other flag values haven't been seen yet.
- **One-sided ranges** (`<5`, `>200`) appear only in `formattedReferenceRange`, with `displayLow` and `displayHigh` empty.
- **Values can be qualified** (`>500`, `<1`) or free text.
- **Text values** use `\r\n` line endings and end with a trailing newline.
- **Cultures:** each organism is a separate `Culture` component, and **all of them share one `componentID`**, so don't use it as a unique key. Each value has the form:
  ```
  Organism 1
  <organism name>
  Colony Count Qualitative: <count>
  ```
  Colony counts seen so far include `moderate` and `profuse`.
- **Comment components** (named `Comment`) hold lab notes, e.g. susceptibility notes, and often arrive before the results they describe.
- **Clinician comments** have their text in `providerComments[].content.body`. No separate request is needed.
- **Imaging** has no components and usually no text here. It names a report through `reportDetails.reportID`; see the next section.

### Imaging report

`POST api/report-content/LoadReportContent`

```json
{
  "reportID": "<reportDetails.reportID>",
  "assumedVariables": { "ordId": "<reportVars.ordId>", "ordDat": "<reportVars.ordDat>" },
  "isFullReportPage": false,
  "uniqueClass": "EID-<any>",
  "nonce": "<32 hex characters>"
}
```

`uniqueClass` and `nonce` only scope the returned CSS, so any values work.

**Response**

```json
{ "reportContent": "<div …><table>…Study Result…</table>…<div class=\"p0_…\"><span>REPORT</span></div>…</div>",
  "reportCss": "<style …>…</style>",
  "baseFontSize": 0,
  "stylesheets": ["/MyRCHPortal/en-AU/styles/report/epicbase.css?v=…"] }
```

`reportContent` is HTML: a heading table ("Study Result", "Narrative & Impression"), then one `<div>` per paragraph, with `&nbsp;` for blank lines. It includes an embedded `<style>` block and `<!--RTF Start-->`-style comments.

### Visit documents

Past visits use the same `POST api/report-content/LoadReportContent`, with `Referer: …/app/visits/past-details?csn=<csn>`. The context fields differ by document type:

| Document | Extra body fields | `reportContent` looks like |
|---|---|---|
| **After Visit Summary** | `"contextLang": "<id>"` | `<h1>After Visit Summary</h1>`, then `pgSection` blocks, each with an `<h2>` section title: Today's Visit (vitals as `vitalsLabel`/`vitalsValue`), What's Next, Medication You Will Be Given, Allergies, Your Medication List and so on. Uses many inline SVG icons. |
| **Notes from the Care Team** (progress note) | `"contextID": "<id>", "contextDAT": "<id>", "contextINI": "HNO"` | `<h1>Progress Notes by <clinician> at <date></h1>`, then RTF-converted paragraphs, as in imaging reports |

Both also send `"reportID"`, `"csn"` (the visit's `Csn`), `"isFullReportPage": false`, `"uniqueClass"` and `"nonce"`. The response has the same shape as for imaging. `reportCss` is nested under `.<uniqueClass>{…}`, so wrap the content in an element with that class. The stylesheet paths are host-relative.

**Listing a visit's notes:** `POST api/visit-notes/GetVisitNotes`

```json
{ "CSN": "<visit Csn>", "FromPvdPage": true }
```

```json
{
  "lrpID": "<notes reportID>",
  "depPhoneNumber": "…",
  "isAtLeastOneNoteSensitive": false,
  "noteList": [
    {
      "hnoID": "<id>", "hnoDAT": "<id>",
      "displayName": "Progress Notes",
      "iso": "2026-03-28T19:03:25+11:00",
      "isAddendum": false,
      "provider": { "name": "<clinician>", "hasPhotoOnBlob": false },
      "isNoteSensitive": false,
      "attachments": []
    }
  ]
}
```

To load a note, send `reportID` = `lrpID`, `contextID` = `hnoID`, `contextDAT` = `hnoDAT` and `contextINI` = `"HNO"`.

**Past-visit details:** `POST api/visits/past-details/GetVisitDetailsPast`

```json
{ "csn": "<visit Csn>", "eorgID": "" }
```

```json
{
  "encounterType": "ambulatory",
  "csn": "<csn>", "dat": "<id>",
  "notesInfo": {
    "isAtLeastOneNoteShareable": true,
    "notesReport": { "reportMnemonic": "OPEN_NOTES", "reportID": "<same as lrpID>" }
  },
  "avsInfo": {
    "hasShareableAvs": true,
    "primaryAvs": { "reportID": "<id>", "reportName": "After Visit Summary", "isEmbeddedPdfReport": false, "url": "" },
    "additionalDocuments": [],
    "languages": [ { "languageID": "<id>", "languageName": "English", "suggested": true } ]
  },
  "visitSummaryInfo": { "department": "…", "provider": "…", "encounterDate": "18 Sep, 2026", "visitType": "Clinic/Practice Visit" }
}
```

To load the After Visit Summary, send `reportID` = `avsInfo.primaryAvs.reportID`, `contextLang` = the `languageID` of the language with `suggested: true`, and the visit's `csn`. Those two IDs have been identical across different visits and sessions: they identify the AVS *report* and the English language, and the `csn` selects the visit. The app still reads them from this response, which also says whether a summary exists (`hasShareableAvs`) and whether any notes do (`isAtLeastOneNoteShareable`). PDF-only summaries (`isEmbeddedPdfReport: true`) and `additionalDocuments` haven't been seen yet.

### Growth charts

`POST api/growth-charts/GetGrowthCharts`, `Referer: …/app/growth-charts`, body `{}`. One response (about 135 KB) holds every reference set, its curves, and the child's measurements.

```json
{
  "datasetIDArray": ["<set id>", "<set id>"],
  "defaultShowImperial": false,
  "datasetDictionary": {
    "<set id>": {
      "displayName": "WHO GIRLS (0-2 YEARS)",
      "dataSource": "WHO Child Growth Standards",
      "growthCharts": {
        "3": {
          "chartTypeId": 3, "chartTypeName": "Weight for Age", "chartType": "weightForAge",
          "xAxisInfo": { "label": "Age (months)", "minVal": 0, "maxVal": 24 },
          "yAxisInfo": { "label": "Weight (kg)", "minVal": 0, "maxVal": 16 },
          "ageInfo": { "type": "chronological", "unit": "months", "min": 0, "max": 24 },
          "curves": [ { "label": "50th percentile", "style": "solid", "points": [ { "xValue": 0, "yValue": 3.2 } ] } ]
        }
      }
    }
  },
  "patientData": {
    "measurementsInfo": {
      "3": {
        "points": [ { "xValue": 4.6, "yValue": 6.1, "date": "28 Jan, 2026", "ageInDays": 140, "ageInMonths": 4.6, "entryType": "Clinic" } ],
        "percentileMap": { "<set id>": ["42.17"] }
      }
    }
  },
  "chartTypeFilterDictionary": { "<set id>": { "3": { "name": "Weight for Age" } } },
  "heightVelocityMap": {}
}
```

- `datasetIDArray` gives the order; the first set is the default. Seen so far: WHO Girls (0–2 years) and CDC Girls (0–36 months), which is sex-specific to the child.
- Chart ids and `chartType`: 1 `headCircForAge`, 2 `lengthForAge`, 3 `weightForAge`, 4 `weightForLength`, 6 `bmiForAge` (WHO only). Weight for Length has length, not age, on the x axis.
- Curves: nine per chart (2nd–98th for WHO, 3rd–97th for CDC). The labels contain typos ("3nd percentile"), so read the number instead.
- Measurements are keyed by chart id and shared by every set. `percentileMap[setID][i]` is the percentile of point `i` against that set, as a string. `chartTypeFilterDictionary` lists the charts that have measurements.
- Dates are `dd MMM, yyyy`.

### Messages

**List:** `POST api/conversations/GetConversationList`, `Referer: …/app/communication-center`

```json
{ "tag": 1, "localLoadParams": { "loadStartInstantISO": "", "loadEndInstantISO": "", "pagingInfo": 1 },
  "externalLoadParams": {}, "searchQuery": "", "PageNonce": "<32 hex characters>" }
```

`tag` picks the folder: `1` inbox, `2` Trash, `3` Bookmarked. The response has `conversations[]`, plus the `users` (care team) and `viewers` (family) they refer to:

```json
{
  "conversations": [
    {
      "hthId": "<conversation id>", "subject": "…", "previewText": "…",
      "hasUrgentMsgs": false, "hasAttachments": false, "tags": { "Messages": true },
      "userKeys": ["<empKey>"], "viewerKeys": ["<wprKey>"], "userOverrideNames": { "<empKey>": "<name>" },
      "messages": [
        { "wmgId": "<id>", "isUnread": false, "deliveryInstantISO": "2026-01-01T00:00:00Z",
          "body": "<div>…</div>", "author": { "displayName": "", "empKey": "<empKey>" }, "attachments": [] }
      ],
      "hasMoreMessages": false
    }
  ],
  "users":   { "<empKey>": { "empId": "<id>", "name": "<clinician>", "providerId": "<id>" } },
  "viewers": { "<wprKey>": { "wprId": "<id>", "name": "<family member>", "isSelf": true } },
  "localSummary": { "hasMoreConversations": false, "numberLoaded": 1 }
}
```

- **Authors:** a care-team message has `author.empKey`, looked up in `users`. `users` keys are sometimes prefixed `ser_`. A family message has `author.wprKey`, looked up in `viewers`, where `isSelf` marks the signed-in account.
- **Bodies** are HTML (`div`, `span`, embedded `style`) with CRLF line endings. Messages are oldest first, with UTC ISO 8601 times.

**Conversation:** `POST api/conversations/GetConversationDetails`, `Referer: …/app/communication-center/conversation?id=<hthId>`

```json
{ "id": "<hthId>", "messageId": "", "organizationId": "", "PageNonce": "<32 hex characters>" }
```

Returns the same conversation fields at the top level, with its own `users` and `viewers`, plus `lastViewedByStaffInstantISO`, `numUnread`, `totalMessages` and `replyFlags.canReply`. Loading it is what the portal's conversation page does, and that marks the thread read.

**Bookmark, Remove Bookmark, Move to Trash, Restore:** `POST api/conversations/Bookmark`, `api/conversations/RemoveBookmark`, `api/conversations/MoveToTrash`, `api/conversations/RestoreFromTrash`, with `Referer: …/app/communication-center/conversation?id=<hthId>`. All four take the same body and reply the same way:

```json
{ "conversationId": "<hthId>", "organizationId": "" }
```

```json
{ "conversationId": "<hthId>", "isSuccess": true, "errors": [], "warnings": [] }
```

The portal's "archive" is its Trash folder, and RestoreFromTrash undoes it. A bookmarked conversation has `"Bookmark": true` in its `tags`.

**Bulk actions** (the list's multi-select): `POST api/conversations/BulkConversationAction`, `Referer: …/app/communication-center`

```json
{ "Conversations": [{ "conversationId": "<hthId>", "organizationId": "" }], "actionType": "BulkUnread" }
```

`actionType` values seen so far: `BulkUnread`, `BulkRemoveBookmark` and `BulkMoveToTrash`. The reply hasn't been captured. There's no bulk bookmark or restore yet, so the app sends one single request per conversation for those. There's also no "mark as read" request: the portal marks a thread read when GetConversationDetails loads it, so the app does the same.

**Reply:** the conversation page's reply box sends these requests, all with `Referer: …/app/communication-center/conversation?id=<hthId>`:

1. `POST api/conversations/GetComposeId` with `{}`. Returns a bare JSON string: the draft's `WP-…` id.
2. `POST api/conversations/SaveReplyDraft`
3. `POST api/conversations/SendReply`, with the same body as the draft. Returns a bare JSON string, the conversation's `hthId`, not an object.
4. `POST api/conversations/RemoveComposeId` with `{ "composeId": "<composeId>" }`. Releases the id and returns a string.

```json
{ "conversationId": "<hthId>", "organizationId": "",
  "viewers": [{ "wprId": "<signed-in family member's wprId>" }],
  "messageBody": ["<text>"], "documentIds": ["<DocumentId>"],
  "includeOtherViewers": true, "composeId": "<composeId>" }
```

- `viewers[].wprId` is the `viewers` entry with `isSelf: true`.
- `messageBody` is an array. Only one-line replies have been captured, so the app sending one entry per line is its best reading of the array, not a verified format.
- **Discarding a draft:** `POST api/conversations/DeleteReplyDraft` with `{ "conversationId": "<hthId>", "organizationId": "" }`, then RemoveComposeId. The app sends both if a reply fails partway through.
- **Closed threads:** `replyFlags.canReply` in GetConversationDetails is false when a conversation can't be replied to.

**Attachments:** `POST /MyRCHPortal/DocumentUpload/UploadFile`, as `multipart/form-data`:

| Field | Value |
|---|---|
| `__file__[]` | the file, with its filename and content type |
| `AddDCSToCache` | `true` |
| `IsPending` | `true` |
| `DCSSource` | `820` |
| `TargetPatientID`, `OrganizationId`, `EncryptDCSOnRemote` | empty |
| `__RequestVerificationToken` | the CSRF token, repeated as a field |

```json
{ "Success": true, "Data": [{ "DocumentId": "WP-…", "FileDisplayName": "photo.png", "FileExtension": ".png",
  "FileReference": "WP-…", "DownloadUrl": null, "AllowPreview": true }] }
```

Each `DocumentId` goes in the reply's `documentIds`.

*Not yet mapped:* SaveReplyDraft's reply, and starting a new conversation.

### Health goals

**Load:** `POST api/goals/LoadPatientGoals`, `Referer: …/app/health-summary`

```json
{ "PageNonce": "<32 hex characters>" }
```

```json
{ "patientGoals": [{ "text": "…", "goalId": "", "goalType": 0, "readings": [], "complianceType": 0,
    "lastUpdatedDate": "28 Sep, 2026", "creationDate": "", "isSharingNotesEnabled": false }],
  "hasChartGraphSecurity": false, "isSharingNotesEnabled": false, "quickLinkDictionary": { … } }
```

**Add:** `POST api/goals/SavePatientGoal`

```json
{ "key": 0, "goal": { "lastUpdatedDate": "28 Sep 2026", "text": "…" } }
```

The portal has a **single free-text goal**, so `key` 0 is that goal, and saving replaces it. The app uses this for both setting and editing the goal. Saving empty text clears the goal. The reply to SavePatientGoal hasn't been captured.

### Explore More

`POST /MyRCHPortal/ExploreMoreFeed?noCache=<random>` with an empty body, `X-Requested-With: XMLHttpRequest` and `Referer: …/Home`. These are the hospital's announcement cards on Home.

```json
{
  "Title": "Explore More for You",
  "ExploreMoreItems": [
    { "EncryptedCctId": "WP-…", "TitleDisplayText": "Kids Health Info",
      "BodyDisplayText": "Check out our Kids Health Info resources…",
      "IconKey": "announcements_information",
      "PrimaryUriDisplayText": "Take me there", "PrimaryUri": "https://www.rch.org.au/kidsinfo/",
      "SecondaryUriDisplayText": "", "SecondaryUri": "" }
  ],
  "Subjects": { "<account id>": "Explore More for <name>", "": "Explore More for You" }
}
```

- `IconKey` is either an image URL on the portal, or a keyword such as `announcements_information`.
- `Subjects` gives each account on the login its own panel title.

### Scans and attachments

```
GET /MyRCHPortal/Clinical/TestResults/BlobScans/BlobScansDownloadOrStream?blobKey=<key>&order=<result key>&displayName=<name>
```

The `downloadUrl` from GetDetails is relative to the host, and already includes the `/MyRCHPortal` base path. `displayName` looks like `Scan - <TEST NAME> - <date>`. The response's file type hasn't been confirmed yet, so the app checks the bytes: `%PDF` means a PDF, otherwise it tries to open an image. An HTML response means the session has expired.

### Medications

`POST api/medications/LoadMedicationsPage`

```json
{ "context": 2 }
```

An empty body gives **HTTP 500**. The value matches `communityMembers[].context` in the response.

**Response** (fields used)

```json
{
  "communityMembers": [
    {
      "context": 2,
      "prescriptionList": {
        "prescriptions": [
          {
            "id": "<id>", "prescriptionNumber": "<n>",
            "name": "sodium chloride 0.9 % solution",
            "patientFriendlyName": "<brand name>",
            "sig": "Inhale 3 mL using a nebuliser…",
            "authorizingProvider": { "name": "<clinician>" },
            "orderingProvider": { "name": "<clinician>" },
            "startDate": "3 March, 2026",
            "dateToDisplay": "…",
            "refillDetails": { "writtenDispenseQuantity": "30", "writtenDispenseUnit": "ampoules", "daySupply": 30 },
            "showRefillButton": false,
            "showPendingUndoDeleteButton": false,
            "isPatientReported": false
          }
        ]
      }
    }
  ]
}
```

Notes:
- The strength is part of `name`, with a space before `%` ("0.9 % solution").
- There's no form field, so the app infers the form (tablet, liquid, inhaled…) from `name` and `sig`.
- `showRefillButton` says whether a repeat can be requested through the portal. The repeat request itself hasn't been mapped yet.

### Health issues (diagnoses)

`POST api/HealthIssues/LoadHealthIssuesData`, `Referer: …/app/health-summary`

```json
{ "isHealthSummary": true }
```

**Response**

```json
{
  "dataList": [
    {
      "healthIssueItem": {
        "name": "Asthma",
        "id": "<id>",
        "formattedDateNoted": "14/01/2026",
        "organization": { "organizationName": "Parkville Precinct", "isLocal": true },
        "isReadOnly": false
      },
      "localItem": { "…same shape…": "" },
      "externalItems": [],
      "hasLocalInstance": true
    }
  ],
  "healthIssuesUrl": "Clinical/HealthIssues"
}
```

`healthIssueItem` merges the hospital's record with any external ones; `localItem` is the hospital's own.

### Letters

**List:** `POST api/letters/GetLettersList`, `Referer: …/app/letters`, body `{}`

```json
{
  "letters": [
    { "dateISO": "2026-09-22", "viewed": true, "hnoId": "<id>", "csn": "<visit csn>",
      "reason": "Referral Letter", "empId": "<author id>" }
  ],
  "users": { "<empId>": { "empId": "<empId>", "name": "<clinician>", "photoUrl": "" } },
  "departments": {}
}
```

Look up each letter's author in `users` by `empId`. `reason` is the letter type. Some values are staff template names, not topics ("Send Notes", "Paste Notes", "Blank"); others are real types ("Referral Letter", "Parent Absence"). Authors can be systems too (e.g. "Batch P" for batch-printed referrals).

**Letter:** `POST api/letters/GetLetterDetails`, `Referer: …/app/letters/details?letterId=<hnoId>&csn=<csn>`

```json
{ "hnoId": "<hnoId>", "csn": "<csn>", "PageNonce": "<32 hex characters>" }
```

Returns just `{ "bodyHTML": "…" }`: the letter as Word-converted HTML, with generated paragraph and span classes (`p0_…`, `s0_…`), tables and links, like progress notes. There's no separate CSS field.

### Immunisations

`POST api/immunizations/LoadImmunizations`, `Referer: …/app/health-summary`, body `{}`

**Response**

```json
{
  "organizationImmunizationList": [
    {
      "organization": { "organizationId": "<org>", "organizationName": "…", "isLocal": true },
      "orgImmunizations": [
        {
          "id": "<id>",
          "name": "Influenza Trivalent (egg-based) >= 6 months",
          "formattedAdministeredDates": ["22 Jun, 2026", "11 May, 2026"]
        }
      ],
      "showViewDetailsLink": true
    }
  ],
  "showPersonalNotes": true,
  "immunizationsUrl": "Clinical/Immunizations"
}
```

There's one entry per vaccine, with **every dose date** in `formattedAdministeredDates`, newest first, in the form `dd MMM, yyyy`. Parse these with a POSIX locale: Australian English abbreviates September as "Sept", so an en-AU parser fails on September dates.

### Immunisation details

`POST api/immunization-details/GetImmunizationDetails`, `Referer: …/app/immunization-details?id=<id>&from=1`

```json
{ "id": "<orgImmunizations[].id>", "name": "", "orgId": "" }
```

The site sends `name` and `orgId` empty.

**Response**

```json
{
  "name": "Influenza Trivalent (egg-based) >= 6 months",
  "immunizationDoses": [
    {
      "administeredDateISO": "2026-06-22",
      "productName": "Vaxigrip",
      "dose": "", "route": "", "site": "", "location": "",
      "manufacturer": "", "lotNumber": "", "ndc": "", "fullName": ""
    }
  ]
}
```

`administeredDateISO` is a date only, with no time. Most fields are often empty, and `productName` is typed by hand, so its capitalisation varies ("Vaxigrip" and "vaxigrip" for the same product). What `fullName` holds hasn't been seen yet.

## Mapping a new endpoint

Every endpoint above was written from a real capture, not a guess. To add one:

1. In Safari, open the portal page with **Web Inspector → Network** open, and clear the log.
2. Do the action on the page and find the new request.
3. Note its **URL and request body**. If you use *Copy as cURL*, delete the `Cookie:` and `__RequestVerificationToken:` lines before saving or sharing it.
4. Copy the JSON from the **Response** tab, replacing any personal values with placeholders.
5. To see which headers actually matter, copy the request as cURL and run:
   ```sh
   python3 Tools/probe_portal_request.py
   ```
   It replays the request from your clipboard once as-is, then once without each header in turn. It prints only header names and status codes.
6. Alternatively, call the endpoint from `MyChartWebService` and log it with `logShape(_:label:)`. That prints the response's keys, types and booleans, with no values.
7. Write the decoder, and mark the endpoint *Verified* in the table above.

## Roadmap

- Map the unverified endpoints: care team, allergies; and messaging actions (reply, new message, archive, bookmark).
- Repeat prescription requests, once the portal's request is captured.
- Reminders on specific weekdays, "as needed" medications, and dose history beyond today.
- **SMART on FHIR** (`EpicFHIRService`): the supported, OAuth-based route for third-party apps. It needs a client registered with RCH/Epic (client ID, redirect URI, scopes) and the hospital's FHIR R4 endpoints.

## Licence

The source code is released under the [MIT Licence](LICENSE).

The licence covers **only the original code and documentation in this repository**. It doesn't grant any rights to:

- the Royal Children's Hospital's names, logos or other trademarks, including any RCH artwork in the app's assets
- Epic Systems Corporation's trademarks
- any data from the portal

If you fork or redistribute this project, replace the RCH logo with your own artwork, and keep the [Disclaimer](#disclaimer).
