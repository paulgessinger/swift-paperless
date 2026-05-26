# HTTP Status codes & testing checklist

- 406: Insufficient API version in all cases
- 400 on `/api/`: general error, could be related to mTLS
- 400 on `/api/token/`: invalid credentials
- 403 on `/api/token/`: can mean autologin is on, no credentials should be POST'ed. Gives CSRF error
- 401 on `/api/ANY`: invalid token (!= invalid credentials)
