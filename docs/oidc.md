# OpenID Connect (OIDC) Login

!!! warning "Beta Feature"
    OIDC login support is currently in beta and may change before the App Store release.

Swift Paperless can sign in using OpenID Connect (OIDC) providers configured on
your Paperless-ngx server. This flow relies on a mobile-friendly OIDC setup
with PKCE and a custom callback URL.

## Provider Requirements

- The provider must be a true OIDC provider (not OAuth2-only), with a valid
  discovery document.
- The provider must support PKCE for public clients **without a client
  secret**, since a client secret cannot be safely stored in the app.
- The provider must support linking social identities to Paperless accounts, so
  OIDC users can map to existing Paperless-ngx users.
- The OIDC client must register the callback URL `x-paperless://oidc-callback`
  so the IdP can return control to the app after authentication.

## Callback URL

Ensure the IdP application configuration includes the following redirect URI:

```
x-paperless://oidc-callback
```

The app listens for this callback to capture the authorization code and
complete the token exchange.
