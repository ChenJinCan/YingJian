# Local Release Contract

Every application uses the same release boundary:

1. Read the currently public version, latest uploaded marketing version, and
   highest uploaded build across all version trains in the authenticated store
   console.
2. Freeze the target platform, track, source commit, version, build, and
   authorized terminal stage.
3. Use a clean release worktree whose branch exactly matches its upstream.
4. Build and sign locally. GitHub Actions is not a packaging or upload path.
5. Verify the final artifact identity and SHA-256 before any upload.
6. Report build, upload, processing, tester access, review, approval, and public
   availability as separate states.

`release/release-policy.yaml` is the committed, non-secret contract. It defines
store identifiers, required tools, environment-file paths, and variable names.
Actual values live only in ignored local files based on the committed examples.
A platform marked `release_ready: false` is intentionally blocked until its
signing and artifact verification path is implemented.

Version and build identity never belongs in `.env.testflight` or `.env.android`.
After a store lookup, supply these runtime values:

- `VERSION` / `BUILD_NUMBER` for iOS, or `VERSION_NAME` / `VERSION_CODE` for
  Android. Pass them to Flutter as `--build-name` and `--build-number`; do not
  persist them in an environment file.
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
or building. The preflight also rejects missing/forbidden environment variables,
dirty worktrees, and branches ahead of, behind, or diverged from their upstream.
