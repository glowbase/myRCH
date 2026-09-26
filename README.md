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

**Dashboard**
- Greeting, age and **MRN**. Tap the MRN for a large-print sheet to show hospital staff, with a copy button.
- Diagnosis and allergy pills linking to the health summary
- Upcoming appointments, recent results, current medications and immunisations
- Quick links to every section, and pull to refresh

**Test results**
- Results grouped by month, with search and filters (type, unread, outside normal range)
- A **within / outside normal range** pill on each result, loaded as rows scroll into view
- Per-test icons: microbe for cultures, blood drop for blood counts, lungs for chest imaging, and more
- Result detail:
  - each value with a **range graph**, including one-sided ranges such as `<5` or `>200`, and qualified values such as `>500`
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
- **Personal notes** per medication, kept only on the device

**Also**
- Appointments with preparation steps and visit summaries
- Health summary: health issues, allergies and immunisations
- Growth charts against WHO/CDC reference percentiles
- Messages with the care team
- Proxy access: switch between children linked to one parent account
- Sign in with the portal's two-step verification code, and optionally remember the device

## Requirements

| Item | Version / note |
|---|---|
| Xcode | With the iOS 27 SDK |
| iOS deployment target | 27.0 |
| Swift | 5 language mode |
| Apple Developer Program | **Paid membership required** for the *Time Sensitive Notifications* capability, which lets reminders break through Focus modes. A free team can't sign the app with this capability; see below. |
| Portal account | A My RCH Portal login, only for live mode. Demo mode needs none. |

## Getting started

1. Clone the repo and open `RCH Portal.xcodeproj`.
2. In **Signing & Capabilities**, choose your **Team** and set a real **Bundle Identifier** (e.g. `au.yourname.myrch`). The placeholder `devplaceholder.…` ID can only use a wildcard profile, which can't carry the Time Sensitive capability.
   - No paid membership? Remove the Time Sensitive capability and change `content.interruptionLevel` in `MedicationStore.swift` to `.active`. Reminders still work, but a Focus mode will silence them.
3. Build and run on a device or simulator.
4. On the sign-in screen, choose the mode:
   - **Demo mode (default):** runs entirely on local sample data from `MockPortalService`, with no network access.
   - **Live portal:** turn on the live toggle and sign in with your My RCH Portal username and password. The first sign-in asks for a verification code sent by SMS or email; choose "remember this device" to skip it next time.

## Project structure

```
RCH Portal/
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
Tools/
└── probe_portal_request.py        Finds which headers a portal request needs
```

Views depend only on the `PortalService` protocol, so the demo, live and future FHIR backends are interchangeable. `Session.service` picks the backend.

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
| Test results list | `POST api/test-results/GetList` | Verified |
| Test result details | `POST api/test-results/GetDetails` | Verified |
| Imaging report | `POST api/report-content/LoadReportContent` | Verified |
| Scans | `GET Clinical/TestResults/BlobScans/BlobScansDownloadOrStream` | Link format verified; file type not yet confirmed |
| Medications | `POST api/medications/LoadMedicationsPage` | Verified |
| Health issues | `POST api/HealthIssues/LoadHealthIssuesData` | Verified |
| Messages | `POST api/conversations/GetConversationList` | Unverified |
| Care team | `POST api/conversations/GetRecipients` | Unverified |
| Growth | `POST api/growth-charts/GetGrowthData` | Unverified |
| Allergies | `POST api/allergies/LoadAllergies` | Unverified |
| Immunisations | `POST api/immunizations/LoadImmunizations` | Unverified |

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

- Map the unverified endpoints: messages, care team, growth, allergies, immunisations.
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
