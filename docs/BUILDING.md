# Building macthermal

There are three ways to build this project. They compile the **same source
files** — the difference is the driver and what each can produce.

- [At a glance](#at-a-glance)
- [Prerequisites](#prerequisites)
- [1. Makefile + `swiftc` (source of truth)](#1-makefile--swiftc-source-of-truth)
- [2. Swift Package Manager (`swift` CLI)](#2-swift-package-manager-swift-cli)
- [3. Xcode](#3-xcode)
- [Which one should I use?](#which-one-should-i-use)
- [How one source tree feeds all three](#how-one-source-tree-feeds-all-three)

## At a glance

| Capability | Makefile (`make`) | SwiftPM (`swift`) | Xcode |
|---|:---:|:---:|:---:|
| Build the CLI | ✅ `make` | ✅ `swift build` | ✅ Run `macthermal` |
| Run the CLI | ✅ `make run` | ✅ `swift run macthermal` | ✅ ⌘R |
| Run the logic tests | ✅ `make test` | ✅ `swift run macthermalTests` | ✅ Run `macthermalTests` |
| Build the GUI **binary** | ✅ | ✅ | ✅ |
| Build the runnable menu-bar **`.app`** | ✅ `make gui` | ❌ | ❌ |
| Editor autocomplete / indexing | — | ✅ | ✅ |
| Used by CI / Homebrew release | ✅ | ❌ | ❌ |

**The one thing only `make` can do:** produce the menu-bar `.app` bundle
(`Info.plist` / `LSUIElement` / icon / signing). SwiftPM and Xcode emit a bare
executable, which does **not** behave as a proper menu-bar agent.

## Prerequisites

Xcode command-line tools (compiler + IOKit headers):

```sh
xcode-select --install
```

The `make` and `swift` paths need only the CLT. Method 3 needs the full **Xcode**
app. Targets macOS 13+, Apple Silicon or Intel. No third-party dependencies.

## 1. Makefile + `swiftc` (source of truth)

The canonical build. It drives releases and the Homebrew tap, so if anything ever
disagrees, **this is what's correct.**

```sh
make            # CLI            -> ./macthermal
make gui        # menu-bar app   -> ./MacThermal.app   (ad-hoc signed, LSUIElement)
make open       # build the app and launch it
make run        # build + run the CLI
make watch      # build + run the live dashboard (1s refresh)
make test       # pure-logic tests — no SMC hardware needed (CI-friendly)
make install    # copy the CLI to $(PREFIX)/bin   (PREFIX defaults to /usr/local)
make clean
```

`make` is timestamp-driven: a no-op rebuild prints `Nothing to be done` — that's
expected, not an error. **Run `make test` after touching `Sources/`.**

Artifacts (`macthermal`, `macthermal-gui`, `MacThermal.app`) are gitignored.

## 2. Swift Package Manager (`swift` CLI)

`Package.swift` is committed as an editor/IDE convenience (see
[AGENTS.md](../AGENTS.md)). It builds and runs the CLI and tests without Xcode.

```sh
swift build                       # build every target into .build/
swift run macthermal              # run the CLI
swift run macthermal --json       # …with arguments
swift run macthermalTests         # run the logic tests (prints the pass count)
```

Targets: a `MacThermalCore` library plus `macthermal`, `macthermal-gui`, and
`macthermalTests` executables that depend on it.

> ⚠️ **No `.app` from SwiftPM.** `swift run macthermal-gui` launches a bare
> executable, not the packaged menu-bar agent. For the real app use `make gui` /
> `make open`.

## 3. Xcode

Open the **manifest** (not the folder — opening the folder gives a plain file
browser with no schemes):

```sh
open -a Xcode Package.swift       # or: xed Package.swift
```

Xcode reads `Package.swift` and offers schemes for `macthermal`,
`macthermal-gui`, and `macthermalTests`, with full autocomplete / jump-to-
definition / inline diagnostics across all files. First open spends a few seconds
resolving/indexing before schemes appear (there are no dependencies to download).

- **CLI** — select `macthermal` → Run (⌘R). Pass arguments via **Product ▸ Scheme
  ▸ Edit Scheme… ▸ Run ▸ Arguments**.
- **Tests** — select `macthermalTests` → Run (▶, not ⌘U — it's a custom runner,
  not XCTest); results print in the console.
- **Menu-bar app** — Xcode builds only the bare binary, same caveat as SwiftPM.
  Build/run the actual agent from a terminal with `make open`.

## Which one should I use?

- **Editing, reading, debugging the CLI/tests** → Xcode (method 3).
- **Quick CLI build/run without opening Xcode** → SwiftPM (method 2).
- **The menu-bar app, an install, a release, or anything CI/Homebrew touches** →
  Makefile (method 1).

## How one source tree feeds all three

The flat `swiftc` build compiles each target as **one module** (shared files
recompiled in); SwiftPM/Xcode compile the shared code as a separate
**`MacThermalCore`** module the front-ends import. Two mechanisms let the same
files satisfy both, so **after changing `Sources/` run both `make test` and
`swift build`**:

- the core's cross-target API is `public`, and
- each entry file imports the core behind `#if canImport(MacThermalCore)` — false
  in the flat build (symbols already in scope), true under SwiftPM/Xcode.

Full details and the `Category`/AppKit gotcha are in
[AGENTS.md ▸ Non-obvious gotchas](../AGENTS.md#non-obvious-gotchas-read-before-editing-the-relevant-file).
