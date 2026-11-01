# Building releases through CI

`just release` runs the existing TestFlight build/sign/upload flow with a
configurable application source ref:

```sh
just release                              # source: main
just release --ref release/v1.10           # source: release branch
just release --ref release/v1.10 --dry-run # CI archive/export, no upload or tag
```

`just beta` is an alias for the same command. App Store submission remains a
separate manual step.

## Branching model

`main` is the trunk: all development lands there and regular betas build from
it. Each minor version gets one `release/vX.Y` branch, and individual versions
are tags on it (`vX.Y.Z`).

There is no long-lived production branch. Release branches are never merged
back, so they can be left behind once the next minor ships.

### Cutting a minor release

1. Create `release/vX.Y` from `main` when the release freezes.
2. On `main`, bump `MARKETING_VERSION` to the next version and empty
   `current_changelog.txt`. Development carries on without a freeze.
3. Build release candidates with `just release --ref release/vX.Y`.
4. Tag the build you submit to the App Store as `vX.Y.Z`.

Keep the gap between minor releases short. Hide large unfinished work behind a
flag in `swift-paperless/FeatureFlags.swift` so `main` stays releasable.

### Patch releases

If `main` is releasable, ship the next minor instead of a patch. Otherwise, use
the existing `release/vX.Y`:

1. Land the fix on `main` first, then cherry-pick it to the release branch and
   name the `main` commit in the message (`git cherry-pick -x` adds this).
   Commit directly to the release branch only when the affected code no longer
   exists on `main`.
2. Add the changelog bullet on both branches.
3. Set the new patch version on the release branch and build from it.

Keep patch releases to fixes and work tied to an outside deadline, such as
support for a new OS or device.

## What CI does

1. Takes release tooling from `main`, independently of the application source.
2. Checks out the selected source commit and reads its version, Xcode version,
   project configuration, dependencies, and changelog.
3. Assigns the next build number through App Store Connect without committing it.
4. Archives, signs, exports, and uploads the app to TestFlight.
5. Creates `builds/<version>/<build>` and its GitHub prerelease at the application
   commit after a successful upload, using the changelog delta for that build.

The source must already be on GitHub. The local command shows the source ref,
resolved commit SHA, and marketing version before dispatching. Moving the branch
afterwards cannot change what gets built.

CI calculates the per-build changelog from its full source history and build tags,
and displays it in the run log and summary before building. The local command
does not fetch or calculate changelog entries. With no previous build, CI shows
all current notes; an unchanged changelog shows no new entries.

There is one workflow, `.github/workflows/beta.yml`. It runs on `main`; its
`source_ref` input selects the application checkout. Old maintenance branches
don't need the tooling backported. They must use the XcodeGen layout and
`Config/Shared/Version.xcconfig` used by the 1.10.x series. This does not migrate
older project layouts or fix source incompatibilities with newer toolchains.

## Options and setup

- `--build-number N`: explicitly select a build number.
- `--yes`: skip the local dispatch confirmation.
- `--dry-run`: still dispatch CI and archive/export; run ASC's upload dry-run,
  without uploading or creating a tag.
- `--workflow-ref BRANCH`: test a pushed version of the release tooling before
  merging. The existing TestFlight workflow must be known on the default branch.
- `--repo OWNER/REPO`: override the default repository.

Local dispatch needs Python 3, just 1.29+ and authenticated `gh`. It works from
Git checkouts and jj workspaces without local ASC credentials. CI uses the
existing Xcode runner, ASC credentials, distribution certificate, and profiles.

An app-wide concurrency group prevents CI uploads for different versions from
racing to allocate the same build number. GitHub keeps at most one pending run;
a newer pending dispatch may replace an older pending dispatch. Local
`just beta-ci` uploads are outside that lock, so avoid running them alongside CI.

If upload succeeds but tagging fails, recover the tag using the instruction in
the CI log rather than uploading the same build again. Avoid mixing the old
Fastlane/prerelease-triggered pipeline with the shared pipeline for a candidate.

The CI branch filters include `develop/**` and `release/**`. Existing maintenance
branches retain their own validation workflows until those are updated.

## Testing

`just release-test` uses uv to run offline pytest tests for pinned source
dispatch, default and explicit build numbers, failure handling, and source/tooling
separation. Fake
GitHub and Xcode tools are used; the tests cannot upload or sign an app.

The exported IPA uses normal App Store Connect distribution, so eligible builds
can be assigned to internal TestFlight testers and later selected for App Review.
Uploading does not itself assign tester groups. TestFlight's Previous Builds
view exposes other available versions, subject to Apple's eligibility rules and
the 90-day expiry. See [Apple's guide](https://testflight.apple.com/).
