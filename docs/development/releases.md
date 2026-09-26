# Building releases through CI

`just release` runs the existing TestFlight build/sign/upload flow with a
configurable application source ref:

```sh
just release                              # source: main
just release --ref release/1.10           # source: maintenance branch
just release --ref develop/v1.10.3        # existing branch names also work
just release --ref release/1.10 --dry-run # CI archive/export, no upload or tag
```

`just beta` is an alias for the same command. `scripts/beta.sh` remains a
compatibility entry point. App Store submission remains a separate manual step.

## What CI does

1. Takes release tooling from `main`, independently of the application source.
2. Checks out the selected source commit and reads its version, Xcode version,
   project configuration, dependencies, and changelog.
3. Assigns the next build number through App Store Connect without committing it.
4. Archives, signs, exports, and uploads the app to TestFlight.
5. Creates `builds/<version>/<build>` and its GitHub prerelease at the application
   commit after a successful upload, using the changelog delta for that build.

The source must already be on GitHub. The local command previews its accumulated
changelog and resolves the source ref to a commit SHA before dispatching, so
moving the branch afterwards cannot change what gets built. CI derives the
per-build notes from the source history and build tags.

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

Use `main` for development and one maintenance branch such as `release/1.10`
while supporting an older version; individual versions remain tags. The CI
branch filters include `develop/**` and `release/**`. Existing maintenance
branches retain their own validation workflows until those are updated.

## Testing

`just release-test` runs offline tests for pinned source dispatch, default and
explicit build numbers, failure handling, and source/tooling separation. Fake
GitHub and Xcode tools are used; the tests cannot upload or sign an app.

The exported IPA uses normal App Store Connect distribution, so eligible builds
can be assigned to internal TestFlight testers and later selected for App Review.
Uploading does not itself assign tester groups. TestFlight's Previous Builds
view exposes other available versions, subject to Apple's eligibility rules and
the 90-day expiry. See [Apple's guide](https://testflight.apple.com/).
