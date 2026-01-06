# Deep Links

!!! warning "Beta Feature"
    Deep link support is currently in development and not yet available in the App Store version. This feature will be available in an upcoming release.

Deep links allow you to open specific content or trigger actions in Swift Paperless from external sources like shortcuts, automation apps, or other applications. Swift Paperless uses the custom URL scheme `x-paperless://` for deep linking.

## URL Structure

All deep link URLs follow this structure:

```
x-paperless://v1/<resource>/<id|action>[?parameters]
```

- **Scheme**: `x-paperless://` (required)
- **Version**: `v1` (required, currently only v1 is supported)
- **Resource**: The type of resource or action (e.g., `document`, `action`)
- **Path**: Resource-specific path (e.g., document ID, action name)
- **Parameters**: Optional query parameters (e.g., `server`, `tags`, `tag_mode`)

## Common Parameters

These parameters can be used with any deep link:

### `server` (optional)

Specifies which Paperless-ngx server to use when opening the link. This is particularly useful if you have multiple servers configured in the app.

**Format**: URL-encoded server string without the URL scheme (https://)

The server parameter can be specified in several formats:

- **Without username**: `example.com` or `example.com:8000`
- **With username**: `user@example.com` or `user@example.com:8000`
- **With port**: `example.com:1234` or `user@example.com:1234`

**Examples:**
- `?server=example.com`
- `?server=example.com%3A8000` (URL-encoded `example.com:8000`)
- `?server=user%40example.com` (URL-encoded `user@example.com`)
- `?server=user%40example.com%3A1234` (URL-encoded `user@example.com:1234`)

**Matching behavior:**

When you specify a server parameter, Swift Paperless will search through your configured servers to find a matching one. The matching is done by string comparison of the server identifier without the scheme.

- The server string must exactly match one of your configured servers
- Both the hostname/IP and port must match
- The username (if present) must also match
- If no matching server is found, the link may not work as expected

If the `server` parameter is not specified, the currently active server will be used.

## Supported Actions

### Open Document

Opens a specific document by its ID.

**URL Format:**
```
x-paperless://v1/document/<document_id>[?server=<server>]
```

**Parameters:**
- `document_id` (required): The numeric ID of the document
- `server` (optional): Server specification

**Examples:**
```
x-paperless://v1/document/123
x-paperless://v1/document/456?server=example.com
```

### Scan Document

Opens the document scanning interface.

**URL Format:**
```
x-paperless://v1/scan[?server=<server>]
```

**Parameters:**
- `server` (optional): Server specification

**Examples:**
```
x-paperless://v1/scan
x-paperless://v1/scan?server=example.com
```

### Clear Filter

Clears all active filters on the document list, resetting the view to show all documents.

**URL Format:**
```
x-paperless://v1/clear_filter[?server=<server>]
```

**Parameters:**
- `server` (optional): Server specification

**Examples:**
```
x-paperless://v1/clear_filter
x-paperless://v1/clear_filter?server=example.com
```

### Set Filter

Applies filter parameters to the document list. This is useful for creating shortcuts to specific filtered views.

**URL Format:**
```
x-paperless://v1/set_filter[?server=<server>][&<filters>...]
```

**Parameters:**

#### `tags` (optional)
Specifies which tags to filter by. The format depends on the desired filter type:

- **Omit parameter**: Don't change the current tag filter (useful when only switching servers)
- **Empty value** (`tags=`): Don't change the current tag filter (same as omitting)
- **`any`**: Clear the tag filter (show all documents regardless of tags)
- **`none`**: Show only documents with no tags assigned
- **Comma-separated IDs**: List of tag IDs (e.g., `1,2,3`)
- **Excluded tags**: Prefix tag IDs with `!` to exclude them (only works with `tag_mode=all`)

#### `tag_mode` (optional)
Controls how multiple tags are combined. Defaults to `any`.

- **`any`**: Documents must have at least one of the specified tags (OR logic)
- **`all`**: Documents must have all specified tags (AND logic)

**Filter Behavior:**

| tags parameter | tag_mode | Result |
|---------------|----------|--------|
| (omitted) | (any) | Current filter unchanged |
| `` (empty) | (any) | Current filter unchanged |
| `any` | (any) | Clear filter - show all documents |
| `none` | (any) | Show documents with no tags |
| `1,2,3` | `any` (default) | Documents with tag 1 OR 2 OR 3 |
| `1,2,3` | `all` | Documents with tag 1 AND 2 AND 3 |
| `1,2,!3,!4` | `all` | Documents with tags 1 AND 2, but NOT 3 or 4 |
| `1,!2` | `any` | Invalid (excluded tags not allowed with `any` mode) |

**Examples:**

Show documents with any of tags 1, 2, or 3:
```
x-paperless://v1/set_filter?tags=1,2,3
x-paperless://v1/set_filter?tags=1,2,3&tag_mode=any
```

Show documents with all of tags 1, 2, and 3:
```
x-paperless://v1/set_filter?tags=1,2,3&tag_mode=all
```

Show documents with tags 1 and 2, but not tags 3 or 4:
```
x-paperless://v1/set_filter?tags=1,2,!3,!4&tag_mode=all
```

Show documents with no tags:
```
x-paperless://v1/set_filter?tags=none
```

Clear tag filter (show all documents):
```
x-paperless://v1/set_filter?tags=any
```

#### `correspondent`, `document_type`, `storage_path`, `owner` (optional)
Simple ID-based filters. All of these share the same format:

- **Omit parameter** or **empty value**: Don't change the current filter
- **`any`**: Clear this filter (show all documents regardless of that field)
- **`none`**: Show only documents with no value assigned
- **Comma-separated IDs**: Include any of these IDs (e.g., `1,2,3`)
- **Excluded IDs**: Prefix IDs with `!` to exclude them, but only when all values are excluded
  (e.g., `!1,!2`). Mixed include/exclude values are treated as include-only and ignores
  excluded IDs.

**Examples:**
```
x-paperless://v1/set_filter?correspondent=1,2
x-paperless://v1/set_filter?document_type=none
x-paperless://v1/set_filter?storage_path=!3,!4
x-paperless://v1/set_filter?owner=any
```

#### `search` and `search_mode` (optional)
Full-text search configuration.

- **`search`**: Search text
- **`search_mode`**: `title`, `content`, `title_content`, or `advanced`

**Examples:**
```
x-paperless://v1/set_filter?search=invoice
x-paperless://v1/set_filter?search=contract&search_mode=content
```

#### `asn`, `asn_gt`, `asn_lt` (optional)
Archive Serial Number filtering.

- **`asn=any`**: Clear ASN filter
- **`asn=null`**: Only documents without ASN
- **`asn=not_null`**: Only documents with ASN
- **`asn=<number>`**: Exact match
- **`asn_gt=<number>`**: Greater than
- **`asn_lt=<number>`**: Less than

If `asn` is provided, `asn_gt` and `asn_lt` are ignored.

**Examples:**
```
x-paperless://v1/set_filter?asn=123
x-paperless://v1/set_filter?asn_gt=100
```

#### `date_created`, `date_added`, `date_modified` (optional)
Date range filters. Each supports a preset range or an explicit between range.

Preset values:
- `any`
- `within_7d`, `within_1w`, `within_3m`, `within_1y`

Notes:
- `within_<n>d` is only accepted when `n` is a multiple of 7; it is treated as weeks.
- The `within_` values map to rolling ranges (e.g., "within 3 months").

Between values:
- `date_created_from=YYYY-MM-DD`
- `date_created_to=YYYY-MM-DD`
- (and the same for `date_added_*` / `date_modified_*`)

**Examples:**
```
x-paperless://v1/set_filter?date_created=within_7d
x-paperless://v1/set_filter?date_added=within_1m
x-paperless://v1/set_filter?date_modified=within_1y
x-paperless://v1/set_filter?date_created_from=2024-01-01&date_created_to=2024-12-31
```

#### `sort_field` and `sort_order` (optional)
Sorting configuration.

- `sort_field` accepts the API raw values (e.g., `created`, `correspondent__name`,
  `document_type__name`, `storage_path__name`, `archive_serial_number`,
  `custom_field_12`) or these aliases: `asn`, `correspondent`, `document_type`,
  `storage_path`.
- `sort_order` accepts `asc`, `ascending`, `desc`, or `descending`.

**Examples:**
```
x-paperless://v1/set_filter?sort_field=created&sort_order=asc
x-paperless://v1/set_filter?sort_field=correspondent__name&sort_order=desc
x-paperless://v1/set_filter?sort_field=custom_field_12
```

## Error Handling

When a deep link is malformed or invalid, Swift Paperless will display a user-friendly error message explaining what went wrong. The error message will include:

- **Title**: "Invalid Deep Link"
- **Details**: A specific description of the problem
- **Documentation Link**: A link to this documentation page for reference

### Common Errors

The following errors may occur when parsing deep links:

**Invalid URL Format**
- The deep link URL structure is malformed or cannot be parsed
- Example: Missing scheme or malformed components

**Unsupported Version**
- The deep link version is not supported (currently only `v1` is supported)
- Example: Using `x-paperless://v2/...` will show "Unsupported deep link version: v2"

**Unknown Resource Type**
- The resource type in the path is not recognized
- Valid resources are: `document`, `scan`, `set_filter`, `clear_filter`
- Example: `x-paperless://v1/unknown/123`

**Missing or Invalid Document ID**
- Document routes require a numeric document ID
- Example: `x-paperless://v1/document/abc` (non-numeric ID)
- Example: `x-paperless://v1/document` (missing ID)

**Invalid Tag Mode**
- The `tag_mode` parameter must be either `any` or `all`
- Example: `?tag_mode=invalid`

**Excluded Tags in "Any" Mode**
- Excluded tags (prefixed with `!`) can only be used with `tag_mode=all`
- Example: `?tags=1,!2&tag_mode=any` is invalid
- Use `tag_mode=all` instead: `?tags=1,!2&tag_mode=all`

**Invalid Search Mode**
- The `search_mode` parameter must be `title`, `content`, `title_content`, or `advanced`
- Example: `?search_mode=invalid`

**Invalid ASN Value**
- ASN values must be numeric or one of `any`, `null`, `not_null`
- Example: `?asn=invalid`

**Invalid Date Format**
- Date values must be formatted as `YYYY-MM-DD`
- Example: `?date_created_from=2024-13-99`

**Invalid Sort Parameter**
- `sort_field` must be a supported field or alias; `sort_order` must be `asc`/`desc`
- Example: `?sort_field=not_a_field`
