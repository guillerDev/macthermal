---
name: release
description: Releasing and distributing a macOS Swift app — choosing a channel (Mac App Store / Developer ID / Homebrew), versioning from a git tag as the single source of truth, code signing with entitlements + Hardened Runtime, App Sandbox tradeoffs, optional notarization + stapling (developer's choice), automating it from a tag in CI, and Homebrew-cask publishing. Use when cutting/publishing a release, wiring a release pipeline, deciding a distribution channel, or fixing Gatekeeper / notarization / entitlement failures.
---

# Releasing & distributing a macOS Swift app

## 1. Pick a channel — it drives signing, sandbox, and notarization

| Channel | Signing identity | App Sandbox | Notarize | `get-task-allow` |
|---|---|---|---|---|
| **Mac App Store** | App Store cert (via App Store Connect) | **required** | Apple does it | must be absent |
| **Developer ID** (direct download or Homebrew) | Developer ID Application | **optional** | **recommended** (`notarytool`) | must be absent |
| **Ad-hoc / unsigned** (local dev, CI, or direct download with a caveat) | `-` (ad-hoc) or none | as configured | no | left `true` |

Key consequence: **the sandbox is required only for the App Store.** For direct /
Homebrew distribution it's optional — and it *constrains* the app (subprocess
file access needs security-scoped bookmarks, network needs an entitlement,
credential helpers are limited). Decide up front whether you even want it.

**Notarization is likewise optional off the App Store — the developer's call, a
tradeoff, not a requirement.** Notarizing (Developer ID + Hardened Runtime, §4)
lets the download open with no Gatekeeper prompt. Skipping it — shipping ad-hoc-
signed or Developer-ID-signed-but-un-notarized — is a legitimate choice; the cost
is that Gatekeeper quarantines the download, so you document a one-time user
workaround (right-click ▸ **Open**, or `xattr -dr com.apple.quarantine App.app`).
Only the App Store mandates Apple's own review; everything else is opt-in.

## 2. Versioning: the git tag is the single source of truth

Don't hand-edit a version in a plist or constant. Use an annotated SemVer tag
`vMAJOR.MINOR.PATCH`; everything downstream derives from it.

- **MAJOR** breaking, **MINOR** new backward-compatible feature, **PATCH** fixes.
- The leading `v` is on the *tag and release asset* (`App-v1.2.0.zip`); the
  *app/cask version string* drops it (`1.2.0`).
- Tags are immutable and monotonic — never move or reuse one (downloads are pinned
  by checksum).

The build resolves the version in priority order and stamps it in, restoring the
working tree afterward (a `trap`) so nothing is left dirty:

```sh
VERSION="${RELEASE_VERSION:-$(git describe --tags --abbrev=0 | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"   # fresh clone, no tags
# stamp CFBundleShortVersionString + CFBundleVersion in the built Info.plist
```

## 3. Sign with entitlements + Hardened Runtime

A signed build must include the app's `.entitlements` or its sandbox / network /
bookmark permissions are silently lost. Notarization additionally requires the
**Hardened Runtime** (`--options runtime`).

```sh
codesign --force --options runtime \
  --entitlements App.entitlements \
  --sign "Developer ID Application: <Name> (<TEAMID>)" App.app
```

- **`get-task-allow` must be gone** for any distributed build (it allows debugger
  attach; notarization and the App Store reject it). A real Developer-ID / App
  Store identity clears it; ad-hoc `-` leaves it `true`.
- Any **re-sign** later in the pipeline (e.g. after bundling) must **re-pass
  `--entitlements --options runtime`** — a bare `codesign -s -` drops them.
- Sign **inside-out**: nested helpers/frameworks first, the `.app` last.

Verify before shipping:

```sh
codesign -d --entitlements :- App.app     # expect your entitlements, NO get-task-allow
codesign --verify --deep --strict App.app
spctl -a -vvv --type execute App.app      # Gatekeeper assessment
```

## 4. Notarize + staple (Developer ID / direct / Homebrew) — optional

Optional but recommended for a frictionless download. Skip this whole section if
you're deliberately shipping an un-notarized build (see §1) — just ship the
zip / `.app` and document the quarantine workaround. When you *do* notarize:

```sh
ditto -c -k --keepParent App.app App.zip
xcrun notarytool submit App.zip --keychain-profile <profile> --wait
xcrun stapler staple App.app              # so it validates offline
```

Store the notary credentials once with
`xcrun notarytool store-credentials <profile>`. If notarization is rejected, run
`xcrun notarytool log <submission-id> --keychain-profile <profile>` — usual causes
are a missing Hardened Runtime, `get-task-allow` present, or an unsigned nested
binary.

## 5. Automate from a tag (CI)

A tag-triggered pipeline keeps releases reproducible:

```
git tag vX.Y.Z && git push --tags
  └─> release workflow (on a macOS runner):
      1. resolve version from the tag
      2. build the .app (version stamped in)
      3. sign — ad-hoc, or Developer ID + entitlements + runtime
      4. (optional) notarize → staple
      5. zip + sha256
      6. create the GitHub Release with the asset
      7. (optional) update the Homebrew cask / formula
```

Keep signing secrets in CI secrets (base64 the `.p12`, import to a temp keychain);
never commit them. Run any project generation (`xcodegen generate`) and dependency
resolution as the first step — see the `swift-build-test` skill.

## 6. Homebrew-cask distribution (optional)

Publish a **cask** in a tap repo (`homebrew-<tap>`). The cask pins the download
`url` (derived from `version`) and a `sha256`. Best practice: keep a cask
**template in the app repo** and regenerate the tap's cask on each release
(substituting version + sha), so:

- the in-repo template is authoritative — edit the cask there, never in the tap;
- template fixes (DSL deprecations like `depends_on macos:`) propagate next release;
- manual edits in the tap get overwritten.

Users then `brew install --cask <tap>/<app>`.

## Troubleshooting

- **Gatekeeper blocks the download** — the build is un-notarized. If you intend to
  notarize, that's the fix (notarize + staple). If you're deliberately shipping
  un-notarized, this is expected — document the one-time workaround (right-click ▸
  **Open**, or `xattr -dr com.apple.quarantine App.app`); it's a caveat, not a bug.
- **Sandbox permissions missing at runtime / notarization rejected** — a re-sign
  dropped the entitlements or left `get-task-allow=true`. Re-sign with
  `--entitlements` + a Developer-ID identity; verify with `codesign -d --entitlements :-`.
- **Version doesn't match the tag** — the build didn't read the tag; check the
  version-resolution env/step and that it stamps the built `Info.plist`.
- **CI can't build** — the runner's Xcode/Swift is too old for the project's
  tools version; pin the image / select Xcode explicitly.

## Notes for the assistant

- To bump the version, **create a tag — never edit a plist**. Confirm the exact
  `vX.Y.Z`, and **do not push tags without explicit confirmation** (a tag is an
  immutable release).
- **Notarization is the developer's decision, not a default** — some apps are
  notarized, others ship un-notarized (ad-hoc or Developer ID) with a documented
  quarantine workaround. Don't add it unless the project wants it. *If* you sign /
  notarize for distribution, the build must use `.entitlements` + Hardened Runtime
  and must not carry `get-task-allow`.
- Decide the channel first (it dictates sandbox + signing); don't enable the App
  Sandbox reflexively for a Developer-ID/Homebrew app.
