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

When you turn the feature on, **and only then**, the app starts preparing a package that contains information about your install, software versions and features. For each complete day, and only once a day at most, the app will attempt to send information to the usage server.

Below you can find information on what exactly is collected locally and periodically sent to the usage server:

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

Below you can see an example payload that looks exactly like the ones the app sends. You can in fact see the json payload with the exact contents that the app will send under **Settings → Anonymous usage → What's sent**.

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

To understand which features are relevant to roughly how many users, the app sends a list of features that were used in the relevant day. I tried to come up with a system that reveals as little as possible.

The app counts the number of times each feature was used, but only sends a rough bucket of usage: once, 2–9 times, 10 or more. This is used to help separate occasionally used features from features that are used all the time.

The data also contains a list of the features that are available to you. This is needed to calculate normalized usage fractions, otherwise an unavailable feature looks exactly like an unused one.

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
  "features" : {
    "document_edit" : "10+",
    "filter" : "1",
    "scan_started" : "1",
    "scan_uploaded" : "1",
    "search" : "2-9"
  }
}
```

## Error Reports

The app also keeps a daily report of the types of errors encountered. This is very coarse information, it only contains the category, for example "certificate error" or "server too old", never any error details that could leak information about your install or library.

- Example (the same features report, on a day with an error):

```json
{
  "available" : [ … ],
  "channel" : "appstore",
  "day" : "2026-11-06",
  "errors" : [
    "timeout"
  ],
  "features" : { … }
}
```

## What is never sent

- Documents, titles, contents, tags, correspondents, any other server data
- Server address, username, anything typed
- Search terms, filter values
- Any identifier: no account, device ID, advertising ID, nothing stable across days
- Device model, region, custom server build tags

## How it's protected

The primary goal here is to build something that is as anonymous as feasible. The data collected already intentionally does not include any account or device identifiers, making it impossible to directly connect reports that way. The IP addresses used to submit the reports are not logged, and only briefly held in memory in the web server to prevent abuse.

Despite all of that, it would theoretically be possible anyway to *fingerprint* data based on the correlation between variables, say a particular backend version in combination with a particular iOS version. To mitigate this, the usage collector server decomposes the tuples of data that come in right away, and then increments independent counters per attribute, e.g. backend version . This essentially avoids storing any correlated information, making it very hard to do any kind of fingerprinting.

The app and the usage collector are open source: sender and receiver code are both in the [Swift Paperless repository](https://github.com/paulgessinger/swift-paperless), so you can read exactly what it does.

## What it reveals

Overall, here’s what the sent data tells me a about you:

- Your install was used that day; unavoidable
- The report's date reveals the last day the app was used before the current one
- The first-this-month / first-this-week answers reveal whether the install was already used earlier that month or week (UTC; weeks start Monday)
- TestFlight reports are counted separately from App Store ones

## Turning it off

If you opted in and change your mind, you can turn the usage system off in **Settings → Anonymous usage**. From that moment, nothing more is sent and the on-device bookkeeping (days not yet reported, opt-in date, month and week of the last report, pending counts) are deleted immediately
