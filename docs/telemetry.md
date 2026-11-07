# Anonymous usage statistics

Swift Paperless can share a small amount of anonymous information about how the
app is used. It is **off unless you turn it on**, and you can turn it off again
at any time in **Settings → Anonymous usage**.

## Why

Swift Paperless is built by one developer in their spare time. Knowing which
Paperless-ngx versions are still in use, whether iPad matters, and which
features people actually rely on helps decide what to build, what to fix first,
and when it's safe to drop support for old versions.

## What is sent

At most once a day, while you're using the app, it sends two short reports.
They are sent separately and contain nothing that connects them to each other.

**Your setup**

| What | Example |
|---|---|
| Whether you got the app from the App Store or TestFlight | App Store |
| App version | 1.11.2 |
| iOS version, without the last number | 18.3 |
| Device type | iPhone or iPad, never the model |
| App language | English, never your region |
| Paperless-ngx version of the server you're using, without any build tags | 2.14.3 |
| Rough library size | under 1,000 / 1,000–10,000 / over 10,000 documents |
| How you sign in | token, password, single sign-on, or none |
| Whether you use a client certificate or custom headers | yes / no |
| Whether you have more than one server set up | one / more than one |
| On how many days this month you opened the app | 1 / 2–7 / 8–20 / 21+ days |
| Roughly how long ago you started sharing | under a week / under a month / under a year / longer |
| Kinds of connection problems seen that day | for example "certificate error" or "server too old" |

**Features you used**

Which features you used that day, and roughly how often: once, a few times, or
10 or more times. For example: "saved views: a few times". The report also lists
which features are available to you, so a feature that your server doesn't
support isn't mistaken for one nobody uses. On days you didn't use any of them,
the report is empty.

You can see the exact reports your device would send right now in
**Settings → Anonymous usage → What's sent**.

## What is never sent

- Your documents, their titles, contents, tags, correspondents, or any other
  data from your server
- Your server's address, your username, or anything you type
- Search terms or filter values
- Any identifier for you or your device: no account, no device ID, no
  advertising ID, nothing that stays the same from one day to the next
- Your device model, your region, or custom build tags of your server

## How it's protected

- **Nothing to link reports together.** Reports carry no identifier, and the two
  daily reports are sent separately. The server cannot tell that two reports
  came from the same device, on the same day or across days.
- **Only totals are kept.** The server doesn't store reports. It splits each one
  up and adds it to running totals like "412 devices used iOS 18 today", then
  discards it. It only writes those totals after enough reports have come in, so
  no stored data can be traced back to a single report.
- **IP addresses aren't stored.** The server is run by the developer, with no
  third-party analytics service or content delivery network in between. Your IP
  address is used briefly in memory to stop abuse and is never logged or saved.
- **Open source.** The code that sends the reports and the code that receives
  them are both in the
  [Swift Paperless repository](https://github.com/paulgessinger/swift-paperless).

## What it reveals

Any report, however little it contains, tells the server that an install of the
app was used that day. That can't be avoided if anything is sent at all.

If you use a TestFlight build, your reports are counted separately from App
Store ones. Because far fewer people use TestFlight, that makes your reports
somewhat less anonymous within the TestFlight group.

## Turning it off

Turn off **Settings → Anonymous usage**. Nothing more is sent, and the small
amount of bookkeeping the app keeps on your device for these reports (which
days you opened the app, and when you started sharing) is deleted right away.
