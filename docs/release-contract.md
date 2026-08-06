# Local Release Contract

Every application uses the same release boundary:

1. Read the currently public version, latest uploaded marketing version, and
   highest uploaded build across all version trains in the authenticated store
   console.
2. Freeze the target platform, track, source commit, version, build, and
   authorized terminal stage.
3. Use a clean release worktree whose branch exactly matches its upstream.
4. Build and sign locally. GitHub Actions is not a packaging or upload path.
5. Verify the frozen MVP acceptance manifest and every referenced evidence
   digest before packaging, except for an explicitly authorized owner
   TestFlight build used to collect that evidence.
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

For iOS, packaging and TestFlight delivery are intentionally separate commands:

```sh
scripts/build_ios_testflight.sh <version> <build>
scripts/upload_ios_testflight.sh \
  <ipa-path> <artifact-report-path> <version> <build>
```

The build command is local-only. It runs the release preflight, creates one
signed IPA with the committed App Store Connect export options, preserves any
older IPA evidence, and records the new artifact in a candidate-specific
ignored directory. It records a
private artifact report after verifying the bundle ID, version, build, iOS
baseline, permissions, Firebase configuration, provisioning profile, code
signature, App Store distribution entitlements, source commit, and SHA-256. The upload command reruns the preflight,
re-verifies the same IPA and SHA-256, asks Apple to validate it, uploads that
exact package, waits on the same delivery, and requires a stable delivery ID
plus a terminal provider-valid state. It never assigns a TestFlight group,
claims real tester reachability, uploads store metadata, submits App Review, or
releases the app publicly.

Both commands remain fail-closed while `platforms.ios.release_ready` is false.
Turning it true requires current signing and store-state evidence; the presence
of these scripts alone is not release readiness. Packaging also requires the
ignored `.quality/mvp-acceptance.yaml` to bind the exact pushed source commit to
the image corpus gate, formal portrait score gate, usability gate, iOS device
matrix, and final acceptance report. The acceptance checker executes the
repository validators for those structured inputs; arbitrary self-declared
Markdown cannot satisfy the gate. The decision expires after seven days and
must be regenerated for the exact release source.

When the owner explicitly authorizes a TestFlight upload before final MVP
acceptance, set `YINGJIAN_OWNER_TESTFLIGHT_AUTHORIZED=1` only on that exact iOS
build or upload invocation. The preflight then permits only the `build` and
`upload` stages to proceed without `.quality/mvp-acceptance.yaml`, so the signed
candidate can be installed and used to collect device and human evidence. This
runtime authorization is not stored in `.env.testflight`; it does not mark the
MVP accepted, assign testers, submit App Review, or authorize public release.

The build stage does not require App Store Connect credentials. The upload
stage requires the ignored API key configuration. Both stages still require
the current store baseline and exact synchronized source identity.

Version and build identity never belongs in `.env.testflight` or `.env.android`.
After a store lookup, supply these runtime values:

- Candidate version and build are positional wrapper arguments. They are passed
  to Flutter as `--build-name` and `--build-number`; do not persist them in an
  environment file.
- `RELEASE_PUBLIC_VERSION`: current publicly available store version.
- `RELEASE_REMOTE_LATEST_VERSION`: latest uploaded marketing version in the
  store, whether public or still in testing.
- `RELEASE_REMOTE_LATEST_BUILD`: highest uploaded build number across every
  version train for that platform, including processing, failed, invalid,
  TestFlight, draft, and review candidates.
- `RELEASE_BASELINE_VERIFIED_AT`: ISO-8601 UTC timestamp from the store lookup;
  it expires after 30 minutes.
- `RELEASE_SOURCE_COMMIT`: exact pushed commit used for the build.

If `RELEASE_REMOTE_LATEST_VERSION` is higher than `RELEASE_PUBLIC_VERSION`, that
version is still in testing and the candidate must reuse it. If both versions
are equal, the current version is already online and the candidate must
increment only the patch (`C`) component by one. A remote latest version lower
than the public version is an invalid baseline. In every case, the build must
equal `RELEASE_REMOTE_LATEST_BUILD + 1`; changing the marketing version never
resets the build number.

Run the policy tests with:

```sh
bash scripts/test_release_contract.sh
ruby scripts/check_release_contract.rb validate-config
```

Release wrappers invoke `scripts/release_contract_preflight.sh` before signing
or building. The preflight also rejects missing/forbidden stage-specific
environment variables, an incomplete or stale MVP acceptance manifest, dirty
worktrees, and branches ahead of, behind, or diverged from their upstream. The
only acceptance exception is the explicit iOS owner-TestFlight runtime
authorization described above; all other platforms and stages remain
fail-closed.

The current MVP execution and validation target is iOS only. Android packaging,
ADB, emulators, and Play delivery are outside this milestone.
