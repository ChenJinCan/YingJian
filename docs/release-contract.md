# Local Release Contract

Every application uses the same release boundary:

1. Read the currently public version, latest uploaded marketing version, and
   highest uploaded build across all version trains in the authenticated store
   console.
2. Freeze the target platform, track, source commit, version, build, and
   authorized terminal stage.
3. Use a clean release worktree whose branch exactly matches its upstream.
4. Build and sign locally. GitHub Actions is not a packaging or upload path.
5. Run the upload preflight for source synchronization, store identity,
   signing environment, and candidate version/build. Full MVP acceptance is a
   later candidate state and does not block an authorized TestFlight upload.
6. Verify the final artifact identity, distribution profile, signed
   entitlements, required resources, Firebase identity, and SHA-256 before any
   upload.
7. Report build, upload, processing, tester access, review, approval, and public
   availability as separate states.

`release/release-policy.yaml` is the committed, non-secret contract. It defines
store identifiers, required tools, environment-file paths, and variable names.
Actual values live only in ignored local files based on the committed examples.
A platform marked `release_ready: false` is intentionally blocked until its
signing and artifact verification path is implemented.

For iOS, local packaging and TestFlight delivery remain separate. A direct
user request that names TestFlight upload is the initial authorization for one
candidate chain; once its preflight passes, do not ask for another per-upload
human confirmation. That upload chain must use Fastlane/Spaceship only. It
must not use the App Store Connect browser UI.

The repository-owned `fastlane ios beta` lane is the only permitted
TestFlight upload adapter. It builds exactly one candidate through the retained
local wrapper, re-verifies the candidate-specific IPA/report/SHA-256, creates a
private exclusive upload-attempt marker in a machine-scoped ledger shared by
local worktrees/clones, and calls Fastlane/Spaceship once. An
unknown or failed result keeps the attempt marker and therefore blocks an
automatic retry until App Store Connect is reconciled. A successful call writes
a private local upload receipt and stops while provider processing is still
pending. Browser UI and the legacy `scripts/upload_ios_testflight.sh` / `altool`
path remain forbidden fallbacks, not alternate delivery routes.

`platforms.ios.release_ready` is `true` because the local build wrapper, final
IPA verifier, and guarded Fastlane/Spaceship lane are implemented and covered
by the release workflow tests. Readiness does not authorize an upload by
itself and does not bypass the store-baseline, signing, source, candidate, or
artifact-identity gates.

The retained local packaging command is:

```sh
scripts/build_ios_testflight.sh <version> <build>
```

The build command is local-only. It runs the release preflight, creates one
signed IPA with the committed App Store Connect export options, preserves any
older IPA evidence, and records the new artifact in a candidate-specific
ignored directory. It records a
private artifact report after verifying the bundle ID, version, build, iOS
baseline, permissions, Firebase configuration, provisioning profile, code
signature, App Store distribution entitlements, source commit, and SHA-256.
The legacy upload-wrapper filename is retained only as a fail-closed tombstone:
every invocation explains the blocker and exits `78`. Its historical `altool`
invocation has been removed and is forbidden; the stub is not an
authorized TestFlight delivery command or an alternate to Fastlane/Spaceship.

After every upload preflight and artifact-identity gate is satisfied, invoke
the guarded lane with the exact runtime identity rather than persisting
version/build values in an environment file:

```sh
fastlane ios beta --env testflight \
  version:<version> \
  build:<build> \
  source_commit:<full-pushed-source-sha>
```

The `source_commit` lane option must exactly match
`RELEASE_SOURCE_COMMIT`. The lane never supplies a changelog or tester group,
never submits beta/App Review, never changes metadata, and never waits for or
polls provider processing. Version components are canonical decimal integers;
nonzero components with leading zeroes are rejected.

The Fastlane upload lane reruns the preflight, re-verifies the exact IPA and
SHA-256, and stops as soon as Fastlane/Transporter returns success for that
exact IPA, version, and build. It records `uploaded` locally without inventing
an App Store Connect build ID that is not yet available. Provider
processing/valid, TestFlight-group distribution, and tester reachability remain
later one-shot checks; list delay must not trigger a duplicate upload. The lane
stops before metadata mutation, App Review, or public release. Local packaging
and the upload lane remain fail-closed while `platforms.ios.release_ready` is
false.

After upload, candidate acceptance remains separate. Claiming that state
requires the ignored `.quality/mvp-acceptance.yaml` to bind the exact pushed
source commit to the image corpus gate, formal portrait score gate, usability
gate, iOS device matrix, and final acceptance report. Run
`ruby scripts/check_mvp_acceptance.rb <repo-root> <source-commit>` during that
later stage. The checker executes the repository validators for those
structured inputs; arbitrary self-declared Markdown cannot satisfy the gate.
The decision expires after seven days and must be regenerated for the exact
release source. A successful upload does not imply candidate acceptance.

`YINGJIAN_OWNER_TESTFLIGHT_AUTHORIZED` is not a supported exception and the
preflight does not read it. A TestFlight request cannot bypass the Fastlane,
store-baseline, signing, source, candidate, or artifact gates; it does not mark
the candidate accepted, assign testers, submit App Review, or authorize public
release.

The build stage does not require App Store Connect credentials. The upload
stage requires the ignored API key configuration. Both stages still require
the current store baseline and exact synchronized source identity.

Version and build identity never belongs in `.env.testflight` or `.env.android`.
After a store lookup, supply these runtime values:

- Candidate version and build are positional wrapper arguments. They are passed
  to Flutter as `--build-name` and `--build-number`; do not persist them in an
  environment file.
- `RELEASE_PUBLIC_VERSION`: current publicly available store version. Use the
  exact literal `none` only when the authenticated store shows that the app has
  never had a publicly available version.
- `RELEASE_REMOTE_LATEST_VERSION`: latest uploaded marketing version in the
  store, whether public or still in testing.
- `RELEASE_REMOTE_LATEST_BUILD`: highest uploaded build number across every
  version train for that platform, including processing, failed, invalid,
  TestFlight, draft, and review candidates.
- `RELEASE_BASELINE_VERIFIED_AT`: ISO-8601 UTC timestamp from the store lookup;
  it expires after 30 minutes.
- `RELEASE_SOURCE_COMMIT`: exact pushed commit used for the build.

If `RELEASE_PUBLIC_VERSION=none`, the existing remote testing version must be
reused. Otherwise, if `RELEASE_REMOTE_LATEST_VERSION` is higher than
`RELEASE_PUBLIC_VERSION`, that version is still in testing and the candidate
must reuse it. If both versions are equal, the current version is already
online and the candidate must increment only the patch (`C`) component by one.
A remote latest version lower than the public version is an invalid baseline.
In every case, the build must equal `RELEASE_REMOTE_LATEST_BUILD + 1`; changing
the marketing version never resets the build number.

Run the policy tests with:

```sh
bash scripts/test_release_contract.sh
ruby scripts/check_release_contract.rb validate-config
```

Release wrappers invoke `scripts/release_contract_preflight.sh` before signing
or building. The preflight also rejects missing/forbidden stage-specific
environment variables, dirty worktrees, and branches ahead of, behind, or
diverged from their upstream. The Fastlane prerequisite is additional; all
platforms and stages remain fail-closed. Full MVP acceptance is checked only
when the uploaded candidate enters its separate acceptance stage.

The current MVP execution and validation target is iOS only. Android packaging,
ADB, emulators, and Play delivery are outside this milestone.
