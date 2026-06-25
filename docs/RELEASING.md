# Releasing & Homebrew distribution

How to cut a new `macthermal` release and publish it to the Homebrew tap. The
[`release` workflow](../.github/workflows/release.yml) automates almost all of
it — in the normal case a release is just pushing a tag.

- [TL;DR](#tldr)
- [How a release works](#how-a-release-works)
- [The Homebrew tap](#the-homebrew-tap)
- [Automatic formula bump (one-time setup)](#automatic-formula-bump-one-time-setup)
- [Manual fallback](#manual-fallback)
- [First-time tap creation](#first-time-tap-creation)
- [Troubleshooting](#troubleshooting)

## TL;DR

Once the [one-time token setup](#automatic-formula-bump-one-time-setup) is done,
shipping a new version is:

```sh
git tag v0.2.0
git push origin v0.2.0      # or: git push --tags
```

That's it. CI builds, tests, creates the GitHub Release, and updates the tap
formula. Users get it with:

```sh
brew install guillerDev/tap/macthermal     # or: brew upgrade macthermal
```

> Releases run on GitHub Actions, so the repo must be pushed to GitHub first —
> Actions does not run locally. Use [semver](https://semver.org) tags
> (`vMAJOR.MINOR.PATCH`).

## How a release works

Pushing a `v*` tag triggers `.github/workflows/release.yml` on a `macos-latest`
runner. It:

1. **Builds & tests** — `make test`, then `make build` and `make gui`. A test
   failure aborts the release.
2. **Packages the app** — zips the ad-hoc-signed menu-bar app as
   `macthermal-app-<tag>.zip`.
3. **Computes the `sha256`** — GitHub auto-generates a source tarball for every
   tag; Homebrew pins it by hash. The job downloads
   `…/archive/refs/tags/<tag>.tar.gz` and hashes it.
4. **Creates a GitHub Release** — attaches the app zip and writes notes
   containing the `url` + `sha256`.
5. **Bumps the tap formula** — see [below](#automatic-formula-bump-one-time-setup).

You can also run it manually from **Actions ▸ Release ▸ Run workflow** and enter
a tag.

## The Homebrew tap

A "tap" is just a Git repo containing a `Formula/` directory. Ours lives at
**`github.com/guillerDev/homebrew-tap`**:

```
homebrew-tap/
└── Formula/
    └── macthermal.rb      # class Macthermal < Formula
```

### Naming convention

Homebrew prepends `homebrew-` to the tap name you type, so the repo **must** be
named `homebrew-tap`:

| You type | Homebrew resolves to |
|----------|----------------------|
| `brew install guillerDev/tap/macthermal` | repo `guillerDev/`**`homebrew-tap`**, file `Formula/macthermal.rb` |
| `brew tap guillerDev/tap` | `github.com/guillerDev/`**`homebrew-tap`** |

You never write the `homebrew-` prefix, the `Formula/` folder, or the `.rb`
extension in `brew` commands.

### What changes each release

Only two lines of `Formula/macthermal.rb` move — the `url` (new tag) and the
`sha256` (hash of the new tarball). A new tag = a new tarball = a new hash; if
the `sha256` doesn't match, `brew install` aborts with a mismatch error (the
integrity check working as intended). The `head "…"` line never changes.

```ruby
url "https://github.com/guillerDev/macthermal/archive/refs/tags/v0.2.0.tar.gz"
sha256 "…new hash…"
```

## Automatic formula bump (one-time setup)

Step 5 of the workflow rewrites those two lines in `homebrew-tap` and pushes the
commit, so you never edit the hash by hand. Because the default
`GITHUB_TOKEN` can only write to the repo it runs in (`macthermal`), pushing to
the *separate* `homebrew-tap` repo needs its own token. The step is gated on
that secret — `if: env.TAP_TOKEN != ''` — so nothing breaks until you add it.

**1. Create a fine-grained Personal Access Token**
GitHub ▸ Settings ▸ Developer settings ▸ Personal access tokens ▸
**Fine-grained tokens** ▸ Generate new token:
- **Resource owner:** `guillerDev`
- **Repository access:** Only select repositories → **`homebrew-tap`**
- **Permissions:** Repository permissions → **Contents: Read and write**
- Generate and copy the token.

**2. Store it as a secret in the `macthermal` repo**
Settings ▸ Secrets and variables ▸ **Actions** ▸ New repository secret:
- **Name:** `TAP_GITHUB_TOKEN`
- **Value:** paste the token

Both steps are done in the browser — a PAT can't be minted programmatically, and
the secret value should be pasted straight into GitHub's UI, never committed to a
file. Scoping the token to only `homebrew-tap` + `Contents: write` is
least-privilege: it can't touch any of your other repos.

To verify, cut a throwaway release (`git tag v0.0.0-test && git push origin
v0.0.0-test`) and watch **Actions ▸ Release**; the tap should get a new
`macthermal …` commit with the bumped hash. Delete the test tag/release
afterward.

## Manual fallback

If `TAP_GITHUB_TOKEN` is absent, the bump step is skipped — the release still
builds and publishes, you just update the tap yourself. Copy the `url`/`sha256`
from the GitHub Release notes into `homebrew-tap/Formula/macthermal.rb`:

```ruby
url "https://github.com/guillerDev/macthermal/archive/refs/tags/v0.2.0.tar.gz"
sha256 "<value from the release notes>"
```

then `git commit && git push` in the tap repo. Or let Homebrew compute it:

```sh
brew bump-formula-pr --tag v0.2.0 guillerDev/tap/macthermal
```

## First-time tap creation

Already done for this project, but for reference — a tap is just a public repo
named `homebrew-tap` with a `Formula/` dir. Create it empty on GitHub, add
`Formula/macthermal.rb`, push, then `brew install guillerDev/tap/macthermal`.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `repository '…/homebrew-tap' not found` on `brew tap` | The tap repo doesn't exist or is private. It must be **public**. |
| `SHA256 mismatch` on install | The formula's `sha256` doesn't match the tarball — recompute it (`curl -sL <url> \| shasum -a 256`) or re-run the release. |
| Bump step skipped in CI | `TAP_GITHUB_TOKEN` secret is missing or empty — add it (see above). |
| Bump step fails to push | Token lacks **Contents: write** on `homebrew-tap`, or expired. Regenerate. |
| Release step can't create the release | Repo's **Settings ▸ Actions ▸ Workflow permissions** must allow write (the workflow already declares `contents: write`). |
| `brew install` still installs the old version | `brew update` first; Homebrew caches tap contents. |
