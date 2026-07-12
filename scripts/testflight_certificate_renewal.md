# Renewing the TestFlight distribution certificate

A runbook/checklist for when the **Apple Distribution certificate** used to sign
TestFlight builds expires (or is about to). Apple distribution certificates are
valid for **1 year**, so this comes up roughly annually.

For context on the rest of the pipeline, see `scripts/beta.sh` (prepares the
build + cuts the prerelease) and `scripts/beta_ci.sh` (archives, signs, and
uploads via `asc`), which runs from `.github/workflows/beta.yml`.

## What expires and what doesn't

| Asset | Renewal | Notes |
| --- | --- | --- |
| **Apple Distribution certificate** | **Yearly — this doc** | Signs the App Store export. Lives in your login keychain locally and as GitHub secrets in CI. |
| **App Store provisioning profiles** | **When the cert changes** | Export uses *manual* signing, so `beta_ci.sh` installs two fixed-name App Store profiles (see step 6). They're bound to the dist cert(s), so a new cert means they must be recreated/rebound. |
| App Store Connect API key (`AuthKey.p8`) | Does not expire | Used for ASC auth (`asc`) and dev-signing the archive. Only rotate if compromised. |

> **Why the cert and profiles are coupled:** the export step
> (`scripts/beta_ci.sh` + `scripts/ExportOptions.plist`) uses **manual** signing
> with two named App Store profiles rather than automatic/cloud signing (the CI
> API key isn't authorised for cloud signing). Each profile is bound to specific
> distribution certificate(s). Create a new cert and the profiles that reference
> only the old one go `INVALID` — so renewal always covers **both**.

## Symptoms that it's time

- CI job **TestFlight → Build & upload to TestFlight** fails during
  `clean archive` or `-exportArchive` with a signing error such as
  *"No signing certificate 'Apple Distribution' found"* or
  *"...certificate ... has expired"*.
- Local `scripts/beta_ci.sh --no-upload` fails to sign.
- Proactive check (do this ~a month ahead):

  ```bash
  asc certificates list --certificate-type DISTRIBUTION --output table
  # look at the expirationDate column
  ```

## Prerequisites

- `asc` logged in (or the `APP_STORE_CONNECT_*` env exported):
  `asc doctor` should be green. If not: `asc auth login`.
- `openssl` and `gh` on PATH (both already used elsewhere in this repo).
- Run everything from a scratch dir you can delete afterwards — the private key
  is sensitive and **must never be committed**:

  ```bash
  cd "$(mktemp -d)"
  ```

---

## Checklist

### 1. Note the current certificate type and id

Match whatever is currently in use rather than guessing. Modern Xcode uses
**Apple Distribution** (`DISTRIBUTION`); older setups used **iOS Distribution**
(`IOS_DISTRIBUTION`). Both can sign App Store builds.

```bash
asc certificates list --output table
```

Record the `id` and `certificateType` of the expiring cert (call it `$OLD_ID`
and `$CERT_TYPE` below).

> Apple caps the number of distribution certificates (usually 2–3). If
> `create` in step 2 fails with a limit error, revoke the old one first
> (step 8) and retry.

### 2. Create a new certificate + private key

`asc` generates the private key and CSR locally and registers the cert with
Apple in one shot:

```bash
CERT_TYPE=DISTRIBUTION   # or IOS_DISTRIBUTION — match step 1

asc certificates create \
  --certificate-type "$CERT_TYPE" \
  --generate-csr \
  --key-out dist.key \
  --csr-out dist.csr \
  --pretty --output json > cert.json
```

- `dist.key` — the **private key** (stays local, never leaves your machine).
- `cert.json` — contains the issued certificate.

### 3. Extract the certificate and assemble a `.p12`

The `.p12` bundles the private key + issued certificate; it's what both CI and
your local keychain need.

```bash
# Pull the base64 DER cert out of the API response and decode it.
jq -r '.data.attributes.certificateContent' cert.json | base64 -d > dist.cer

# DER -> PEM
openssl x509 -inform der -in dist.cer -out dist.pem

# Bundle key + cert into a password-protected .p12.
# -legacy is required so macOS `security import` (used by beta_ci.sh) can read it.
P12_PASSWORD="$(uuidgen)"        # or pick your own; you'll store it as a secret
openssl pkcs12 -export -legacy \
  -inkey dist.key -in dist.pem \
  -out dist.p12 -passout pass:"$P12_PASSWORD"

echo "p12 password: $P12_PASSWORD"   # copy this — needed in step 4
```

### 4. Update the CI secrets

`beta_ci.sh` reads `DIST_CERTIFICATE_P12_BASE64` (base64 of the `.p12`) and
`DIST_CERTIFICATE_PASSWORD`, imports them into a throwaway keychain, and signs
with them.

```bash
base64 -i dist.p12 > dist.p12.b64
gh secret set DIST_CERTIFICATE_P12_BASE64 < dist.p12.b64
gh secret set DIST_CERTIFICATE_PASSWORD --body "$P12_PASSWORD"
```

Confirm they're set:

```bash
gh secret list | grep DIST_CERTIFICATE
```

### 5. Update your local login keychain

Needed for local `just beta-ci` runs (locally, signing uses the login keychain,
not the CI secrets). Importing the `.p12` installs both cert and private key:

```bash
security import dist.p12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign
```

(Equivalently: double-click `dist.p12` in Finder and enter the password.)

### 6. Rebind the App Store provisioning profiles to the new cert

Export uses **manual** signing with two fixed-name App Store profiles that
`beta_ci.sh` installs by name each run (`APPSTORE_PROFILE_NAMES` in the script;
`provisioningProfiles` in `scripts/ExportOptions.plist`):

| Profile name | Bundle id |
| --- | --- |
| `swift-paperless AppStore CI` | `com.paulgessinger.swift-paperless` |
| `swift-paperless ShareExtension AppStore CI` | `com.paulgessinger.swift-paperless.ShareExtension` |

Each is bound to the distribution cert, so a new cert means they must be
recreated. A profile can't be edited in place — delete the stale same-named one
and create a fresh one bound to the new cert:

```bash
# New cert id (from step 2's cert.json) and the bundle-id resource ids.
NEW_CERT_ID="$(jq -r '.data.id' cert.json)"
APP_BUNDLE="$(asc bundle-ids list --output json | jq -r '.data[] | select(.attributes.identifier=="com.paulgessinger.swift-paperless") | .id')"
EXT_BUNDLE="$(asc bundle-ids list --output json | jq -r '.data[] | select(.attributes.identifier=="com.paulgessinger.swift-paperless.ShareExtension") | .id')"

# Optionally keep the old cert id(s) in --certificate too (comma-separated) so
# in-flight builds signed with the old cert stay valid during the transition.
for pair in "swift-paperless AppStore CI|$APP_BUNDLE" \
            "swift-paperless ShareExtension AppStore CI|$EXT_BUNDLE"; do
  name="${pair%%|*}"; bundle="${pair##*|}"
  old="$(asc profiles list --profile-type IOS_APP_STORE --output json \
    | jq -r --arg n "$name" '.data[] | select(.attributes.name==$n) | .id')"
  [ -n "$old" ] && asc profiles delete --id "$old" --confirm
  asc profiles create --name "$name" --profile-type IOS_APP_STORE \
    --bundle "$bundle" --certificate "$NEW_CERT_ID"
done
```

`beta_ci.sh` re-downloads them by name on every run, so nothing is committed —
the next CI build picks up the rebound profiles automatically.

### 7. Verify

Local end-to-end signing without touching TestFlight (this also installs the
rebound profiles and exercises the manual-signing export path):

```bash
# from the repo root
ALLOW_BUILD_NUMBER_MISMATCH=1 just beta-ci --no-upload   # archive + export with the new cert
# or, to also exercise the ASC upload reservation without publishing:
just beta-ci --bump --dry-run
```

CI: re-run the failed **TestFlight** workflow, or trigger a fresh beta with
`scripts/beta.sh` (`just beta`). Watch the *Build & upload to TestFlight* step
sign and upload cleanly.

### 8. Revoke the old certificate (cleanup)

Once the new cert is confirmed working everywhere (and the profiles no longer
reference it):

```bash
asc certificates revoke --id "$OLD_ID" --confirm
```

### 9. Wipe the scratch dir

The private key and `.p12` are sensitive — delete them:

```bash
cd - && rm -rf "$OLDPWD"   # or just delete the mktemp dir you created
```

---

## Fallback: Xcode / Developer portal (no `asc`)

If `asc` is unavailable:

1. **Xcode → Settings → Accounts → (team) → Manage Certificates → + → Apple
   Distribution.** Xcode creates the cert and stores the private key in your
   login keychain.
2. **Keychain Access → find the new "Apple Distribution" cert → right-click →
   Export** as `dist.p12` with a password.
3. Continue from **step 4** above (base64 + `gh secret set`).

The certificate can also be created manually at
<https://developer.apple.com/account/resources/certificates> by uploading a CSR
generated with *Keychain Access → Certificate Assistant → Request a Certificate
from a Certificate Authority* (keeps the private key local), then downloading
the `.cer` and exporting the `.p12` from Keychain Access.
