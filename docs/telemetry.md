# Anonymous usage statistics

<!-- Draft outline: points to hit under each heading. Replace with your own text. -->


> [!IMPORTANT]
> **tl;dr**
>
> Swift Paperless can **optionally** collect anonymous usage data. This functionality is off by default, and unless you opt in specifically, nothing is ever sent to anywhere other than your server.
>
> If you previously opted in, you can disable usage sharing at any time in: **Settings → Anonymous usage**.

## Why

Swift Paperless is largely developed by a single developer, me, in my spare time. Basically, usage data allows me to focus my time on where it’s most effective in improving the app for users.

Here are some of the types of questions that usage data can answer for me:

- Which Paperless-ngx versions are still in use (can I drop 1.14 support?)
- Which iOS versions do I need to support?
- How much iPad matters
- Which features people actually use


## How does it work and what is sent

- At most once a day per report, while the app is in use
- Two reports, sent separately, one after the other
- No shared field connects the two reports; the server sees both come from the same IP while receiving them, and never stores it

**Your setup**

| What | Example |
|---|---|
| Whether you got the app from the App Store or TestFlight | App Store |
| App version | 1.11.2 |
| iOS version, without the last number | 18.3 |
| Device type | iPhone, iPad or Mac, never the model |
| App language | English, never your region |
| Paperless-ngx version of the server you're using, without any build tags | 2.14.3 |
| API version of that server | 9 |
| Rough library size | under 1,000 / 1,000–10,000 / over 10,000 documents |
| How you sign in | token, password, single sign-on, or none |
| Whether you use a client certificate or custom headers | yes / no |
| Whether you have more than one server set up | one / more than one |
| Roughly how long ago you started sharing | under a week / under a month / under a year / longer |
| Whether this is the first report this month / this week | yes / no |

- Example (health report):

```json
{
  "api" : 9,
  "app" : "1.11.2",
  "auth" : "token",
  "backend" : "2.14.3",
  "channel" : "appstore",
  "client_cert" : false,
  "custom_headers" : false,
  "device" : "iPhone",
  "docs" : "1k-10k",
  "first_month" : false,
  "first_week" : true,
  "install_age" : "<1y",
  "ios" : "18.3",
  "lang" : "en",
  "servers" : "1"
}
```

**Features you used**

- Covers one past day: the last day you used the app, sent the next time you open it
    - carries that day's date (UTC), at most 30 days back
    - days you didn't open the app send nothing
- Which features were used that day, and roughly how often: once, 2–9 times, 10 or more
- Kinds of connection problems seen that day, for example "certificate error" or "server too old"
- Includes uploads from the share extension and the Upload Document shortcut
- Also lists which features are available to you, so an unsupported feature isn't read as unused
- Report is still sent, empty, for an active day without feature use
- Exact reports visible in **Settings → Anonymous usage → What's sent**

- Example (feature report):

```json
{
  "available" : [
    "saved_view",
    "search",
    "filter",
    "document_edit",
    "document_share",
    "scan_started",
    "scan_uploaded",
    "import_started",
    "import_uploaded",
    "network_scan_uploaded",
    "share_extension_uploaded",
    "shortcut_uploaded",
    "notes"
  ],
  "channel" : "appstore",
  "day" : "2026-11-06",
  "errors" : [
    "timeout"
  ],
  "features" : {
    "document_edit" : "10+",
    "filter" : "1",
    "scan_started" : "1",
    "scan_uploaded" : "1",
    "search" : "2-9"
  }
}
```

## What is never sent

- Documents, titles, contents, tags, correspondents, any other server data
- Server address, username, anything typed
- Search terms, filter values
- Any identifier: no account, device ID, advertising ID, nothing stable across days
- Device model, region, custom server build tags

## How it's protected

- No identifier, so nothing links reports across days
- Reports aren't stored; the server keeps only running totals per value, day and channel ("412 devices on iOS 18 today")
- Nothing in storage joins the two reports
- IP addresses:
    - server run by the developer, no third-party analytics or CDN
    - IP used in memory for rate limiting only
    - never logged or stored
- In small groups (e.g. TestFlight, or a rare value), a day's totals can amount to a single install's report
- Accepted because reports contain only coarse values from a fixed list
- Open source: sender and receiver are both in the
  [Swift Paperless repository](https://github.com/paulgessinger/swift-paperless)

## What it reveals

- Any report reveals that an install was used that day; unavoidable
- The features report's date reveals the last day the app was used before the current one
- The first-this-month / first-this-week answers reveal whether the install was already used earlier that month or week (UTC; weeks start Monday)
- TestFlight reports are counted separately from App Store ones
- Fewer TestFlight users, so less anonymity within that group: a day's totals there can be one install's setup and feature use

## Turning it off

- Turn off **Settings → Anonymous usage**
- Nothing more is sent
- On-device bookkeeping (days not yet reported, opt-in date, month and week of the last report, pending counts) deleted immediately
