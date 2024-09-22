# Certificates

!!! note
    This page is a work in progress.

Errors relating to certificates occur when the Paperless-ngx instance is
configured using a self-signed SSL certificate. Such a certificate is not
automatically trusted by the operating system, which then returns an error when
the app tries to connect to the server.

Possible solutions are:

1. Using a trusted SSL certificate, for example from [Let's
   Encrypt](https://letsencrypt.org/).
2. Adding the self-signed certificate or the signing certificate authority
   certificate to the device's trust store at the system level.

## Self-signed certificates

## Mutual TLS (mTLS)
