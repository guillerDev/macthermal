---
name: release
description: >-
  Cut and ship a new macthermal release, or explain the automated release +
  Homebrew publishing pipeline. Use when the user wants to tag/publish a version,
  ship a release, bump the version, or asks how releases, release notes/changelog,
  or the Homebrew tap get updated.
---

# Releasing macthermal

A release is **tag-driven**: pushing a `vMAJOR.MINOR.PATCH` tag triggers
[`.github/workflows/release.yml`](../../../.github/workflows/release.yml), which
builds, tests, publishes a GitHub Release (with a commit-level changelog), and
bumps the Homebrew tap. The tag is the single source of truth for the version —
`VERSION=${TAG#v}` flows into the formula and cask automatically.

**Authoritative reference:** [docs/RELEASING.md](../../../docs/RELEASING.md) —
one-time tap-token setup, tap layout, manual fallback, and the troubleshooting
table. This skill is the *procedure*; that doc is the *detail*. Keep both in sync
with the workflow if you change it.

Actions runs on GitHub, so the repo must be pushed there first — nothing here
runs locally except the preflight.

---

## 1. Preflight (before tagging)

Do these **on `main`, before creating the tag** — CI does not do them for you.

- [ ] **Clean tree, on `main`, pushed:** `git status` clean, `git rev-parse --abbrev-ref HEAD` is `main`, and `git push` so `origin/main` is current.
- [ ] **Pick the semver bump.** patch = fixes, minor = features, major = breaking. Look at `git log $(git describe --tags --abbrev=0)..HEAD --oneline` to justify the level.
- [ ] **`make test`** passes locally (CI reruns it, but catch failures before tagging).

> **You do not bump the app-bundle version by hand.** `make gui` stamps the
> version into the `.app`'s Info.plist at build time from `APP_VERSION` (default:
> `git describe`), so the committed
> [Resources/Info.plist](../../../Resources/Info.plist) stays a static placeholder
> — leave it alone. The GUI embeds `CFBundleShortVersionString` in its diagnostic
> reports (via `SystemProfileProvider` → `DiagnosticContext` → the HTML/CSV report).

**What the stamped version looks like.** It's derived from the git **tag**, not
from the placeholder in Info.plist:

- **Released `.app`** → the exact tag, clean. CI passes `APP_VERSION=${TAG#v}` (e.g. `0.5.1`), and even without that, a clean checkout sitting on the tag makes `git describe` = `v0.5.1` with no suffix.
- **Local `make gui`** → the tag plus build-position info, e.g. `0.5.1-3-g1c72685-dirty`:

  | Part | Meaning |
  |------|---------|
  | `0.5.1` | most recent tag (`v0.5.1`), `v` stripped |
  | `-3` | commits since that tag |
  | `g1c72685` | `g` (git) + abbreviated commit hash |
  | `-dirty` | uncommitted changes in the working tree |

  The suffix is a *local-dev-only* signal (which commit / dirty state a diagnostic report came from); it never appears on a real release. Force a specific value with `make gui APP_VERSION=x.y.z`.

---

## 2. Cut the release

The tag **must** match `v<MAJOR>.<MINOR>.<PATCH>` — the workflow triggers on
`tags: ['v*']` and derives the Homebrew version from it.

```sh
git tag v0.5.2
git push origin v0.5.2        # or: git push --tags
```

That's the whole manual release. Everything below happens automatically on the
runner.

Alternatively, run it from **Actions ▸ Release ▸ Run workflow** and enter the tag
(`workflow_dispatch`) — useful to re-run a release without moving the tag.

---

## 3. What CI does automatically

`release.yml` runs on a **`macos-26`** runner (pinned deliberately: the app must
link against the macOS 26 SDK so the distributed `.app` gets Tahoe SwiftUI
styling; `macos-latest` is still 15). In order:

1. **Checkout** — `fetch-depth: 0` + `ref: <tag>` so the whole history and all tags are present (needed for the changelog range) and the build is the tagged commit.
2. **Show toolchain** — prints `swiftc` + SDK version (diagnosing appearance drift).
3. **Build & test** — `make test`, then `make build` (CLI) and `make gui APP_VERSION="${TAG#v}"` (`.app`). Passing `APP_VERSION` stamps the exact tag into the bundle's Info.plist (see the version note under *Preflight*). A test failure aborts the release.
4. **Package menu-bar app** — `ditto -c -k --keepParent` zips the ad-hoc-signed app to `macthermal-app-<tag>.zip`.
5. **Compute app-zip sha256** (`appsha`) — the cask pins the app by this hash.
6. **Compute source-tarball sha256** (`sha`) — downloads GitHub's auto-generated `…/archive/refs/tags/<tag>.tar.gz` and hashes it; the CLI formula pins it.
7. **Build changelog** — `git describe --tags --abbrev=0 "<tag>^"` finds the previous tag, then `git log --no-merges --pretty='- %s (%h)' <prev>..<tag>` lists every commit, plus a compare link. First release (no previous tag) → lists the entire history. This is a raw `git log` changelog *on purpose*: the repo commits straight to `main`, so GitHub's PR-based `--generate-notes` would be nearly empty.
8. **Write release notes** — prepends the changelog, then the Homebrew install snippet + the `url`/`sha256` values for the tap.
9. **Create GitHub Release** — `gh release create <tag> macthermal-app-<tag>.zip --title <tag> --notes-file notes.md`.
10. **Bump tap formula & cask** — only if the `TAP_GITHUB_TOKEN` secret is set. Clones `guillerDev/homebrew-tap`, rewrites `url`/`sha256` in `Formula/macthermal.rb` and `version`/`sha256` in `Casks/macthermal.rb`, commits, pushes. If the secret is absent this step is skipped and you bump the tap by hand (see [docs/RELEASING.md](../../../docs/RELEASING.md#manual-fallback)).

---

## 4. Verify after the run

- **Actions ▸ Release** — the run is green.
- **Releases page** — the notes lead with the **What's changed** changelog and the `macthermal-app-<tag>.zip` asset is attached.
- **Tap repo** (`guillerDev/homebrew-tap`) — a fresh `macthermal <tag>` commit with the bumped hashes (only if `TAP_GITHUB_TOKEN` is configured).
- **Install** picks up the new version:
  ```sh
  brew update
  brew upgrade macthermal            # CLI
  brew upgrade --cask macthermal     # menu-bar app
  ```

---

## 5. Fixing a bad release

Tags are cheap to redo *before* anyone installs. To redo a version:

```sh
git push --delete origin v0.5.2      # remove the remote tag
gh release delete v0.5.2 --yes       # remove the GitHub Release
git tag -d v0.5.2                     # remove the local tag
# fix the problem, commit, then re-tag and push
```

Prefer a new patch version over re-pushing a tag once a release is public — a
moved tag changes the source tarball, which breaks the `sha256` for anyone who
already fetched it.

---

## Gotchas

- **Info.plist version is stamped at build time, not committed** — `make gui` writes `APP_VERSION` (default `git describe`, CI passes the exact tag) into the bundle's Info.plist, leaving the committed source file a static placeholder. Don't hand-bump it. A local `make gui` reports a `git describe` version (e.g. `0.5.1-3-gabc123-dirty`); pass `make gui APP_VERSION=x.y.z` to force one.
- **Changelog uses commit subjects** — history already follows Conventional Commits (`feat(...)`, `fix(...)`), so it reads cleanly. Sloppy commit messages → a sloppy changelog.
- **`macos-26` is a preview image** — if a run fails on the runner itself (not the build), pin to `macos-15` per the comment in the workflow, accepting the older SwiftUI styling.
- **Tap bump needs its own token** — the default `GITHUB_TOKEN` can't push to the separate `homebrew-tap` repo; `TAP_GITHUB_TOKEN` (fine-grained, Contents:write on `homebrew-tap`) is required. Setup in [docs/RELEASING.md](../../../docs/RELEASING.md#automatic-formula-bump-one-time-setup).
- **`SHA256 mismatch` on install** — the formula hash doesn't match the tarball; re-run the release or recompute (`curl -sL <url> | shasum -a 256`).
- **Never name anything `thermal`** — the product/formula/binary is `macthermal`; `thermal` shadows a system binary and Homebrew rejects it (see [AGENTS.md](../../../AGENTS.md)).
