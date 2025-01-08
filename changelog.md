PLEASE DO NOT SEND ME SCREENSHOTS WITH CONFIDENTIAL DOCUMENTS!
Redact screenshots to not include information that you do not wish to expose.

---

- PLEASE LET ME KNOW IF YOU STILL SEE ISSUES WITH PHOTO IMPORTS!

---

# What's new?

- All new login screen with a new design
  - Improved error handling with more detailed error messages in many scenarios
  - Added the ability to log in with a token or without credentials (auto-auth,
    mTLS, etc)
- Added the ability to change servers when the currently active server is not responding.
- Added shortcut to create a bug report on GitHub from the settings
- Recover from invalid filter rule contents (set manually in the admin backend)
in certain cases
- Explicit handling and detection of unsupported server API versions
  - The server details in the settings now report if the server is running an
    unsupported version
- Added warning when using the `Authorization` header as a custom header
- Improved error output when API response parsing fails
- Add option to log out or switch servers on the loading screen. This is shown
  after a short timeout
- Clarify what the top toolbar dropdown menu means if now saved views exist
- Fix an issue when sharing exported logs via share sheet
- Add ability to swipe down to hide the bottom bar in the document detail view.
  Added a setting to control if this bar is shown by default or not
- Improve error handling of general HTTP errors with the same messages as
  during the login process
- Fix layout issue on iPad that prevented display of the login menu on the home
  document screen
- Attempted fixes for a number of concurrency issues in the document edit
  screen and during photo import
- Fix bug that prevented returning to the start screen after deleting a document
- Improvements to the animation during server switching
- Prepare for granular handling of user permissions
- Improved layout of the document detail screen for larger dynamic text sizes
- Fix for storage path not being added to newly created documents
- Fix ASN not being saved when uploading documents with restricted user accounts
