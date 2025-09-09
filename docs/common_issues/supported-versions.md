# Supported versions

!!! info
    Paperless-ngx is a dynamic project with frequent updates. I'm trying to keep the app working as best as I can! If you notice any issues after upgrading, please [let me know](https://github.com/paulgessinger/swift-paperless/issues/new?template=bug_report.yml).

## API Versions

The app supports Paperless-ngx API versions 3 through 9 (as of September 2025).

For detailed API documentation, see the [official Paperless-ngx API docs](https://docs.paperless-ngx.com/api/).

## Backend Versions

The minimum required Paperless-ngx backend version is [v1.14.1](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v1.14.1) and is tested up to and including version [v2.18.3](https://github.com/paperless-ngx/paperless-ngx/releases/tag/v2.14.7).

## Version Detection

The app automatically detects the backend version and API version by checking the following HTTP headers in responses:

- `X-Version` or `x-version`: Backend version
- `X-Api-Version`: API version

If the backend API version is outside the supported range (3-7), a warning will be logged but the app will still attempt to function by using the closest supported version.
