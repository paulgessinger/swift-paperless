# Login fails for a local address

iOS applications need explicit user approval to be allowed to connect to local network addresses. This is a security feature to prevent apps from connecting to local services without the user's knowledge!

The first time a connection to a local network address is attempted, the app will show a dialog asking for permission to connect to the local network. If this dialog is dismissed, the app will not be able to connect to the local network address.

You can resolved this by navigating to Settings -> Privacy & Security -> Paperless and enabling the "Local Network" switch.
