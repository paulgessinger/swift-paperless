# Anonymous usage statistics

<!-- Draft outline: points to hit under each heading. Replace with your own text. -->

- Off by default; opt-in only
- Toggle: **Settings → Anonymous usage**; can be turned off any time

## Why

- One developer, spare time
- Questions it answers:
    - which Paperless-ngx versions are still in use
    - whether iPad matters
    - which features people actually use
- Decisions it feeds: what to build, what to fix first, when to drop old versions

## What is sent

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
| Rough library size | under 1,000 / 1,000–10,000 / over 10,000 documents |
| How you sign in | token, password, single sign-on, or none |
| Whether you use a client certificate or custom headers | yes / no |
| Whether you have more than one server set up | one / more than one |
| On how many days in the last 30 you opened the app | 1 / 2–7 / 8–20 / 21+ days |
| Roughly how long ago you started sharing | under a week / under a month / under a year / longer |

**Features you used**

- Covers one past day: the last day you used the app, sent the next time you open it
    - carries that day's date (UTC), at most 30 days back
    - days without any use send nothing
- Which features were used that day, and roughly how often: once, 2–9 times, 10 or more
- Kinds of connection problems seen that day, for example "certificate error" or "server too old"
- Includes uploads from the share extension and the Upload Document shortcut
- Also lists which features are available to you, so an unsupported feature isn't read as unused
- Report is still sent, empty, for an active day without feature use
- Exact reports visible in **Settings → Anonymous usage → What's sent**

## What is never sent

- Documents, titles, contents, tags, correspondents, any other server data
- Server address, username, anything typed
- Search terms, filter values
- Any identifier: no account, device ID, advertising ID, nothing stable across days
- Device model, region, custom server build tags

## How it's protected

- No identifier; the two reports are separate and can't be linked, same day or across days
- Server keeps only running totals per value and day ("412 devices on iOS 18 today"), never reports
- Totals are written only after 20 reports have come in, so no write maps to one report
- IP addresses:
    - server run by the developer, no third-party analytics or CDN
    - IP used in memory for rate limiting only
    - never logged or stored
- Open source: sender and receiver are both in the
  [Swift Paperless repository](https://github.com/paulgessinger/swift-paperless)

## What it reveals

- Any report reveals that an install was used that day; unavoidable
- The features report's date reveals the last day the app was used before the current one
- TestFlight reports are counted separately from App Store ones
- Fewer TestFlight users, so less anonymity within that group

## Turning it off

- Turn off **Settings → Anonymous usage**
- Nothing more is sent
- On-device bookkeeping (active days, opt-in date, pending counts) deleted immediately
