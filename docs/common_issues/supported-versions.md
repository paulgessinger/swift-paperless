# Supported versions

## API Versions
The app supports Paperless-ngx API versions 3 through 5.

API versions represent different iterations of the Paperless-ngx REST API:
- v3: Initial stable API with basic document management
- v4: Added support for storage paths and saved views
- v5: Latest version with tasks API and enhanced document metadata

For detailed API documentation, see the [official Paperless-ngx API docs](https://docs.paperless-ngx.com/api/).

## Backend Versions
The minimum required Paperless-ngx backend version is 1.14.1.

## Version Detection
The app automatically detects the backend version and API version by checking the following HTTP headers in responses:
- `X-Version` or `x-version`: Backend version
- `X-Api-Version`: API version

If the backend API version is outside the supported range (3-5), a warning will be logged but the app will still attempt to function by using the closest supported version.
