# AGENTS.md

Guidance for AI agents (and humans) working in this repo. Keep it current when
you change the build, the architecture, or a non-obvious convention.

## What this is

`macthermal` is a dependency-free macOS temperature & fan-speed analyzer that
reads the System Management Controller (SMC) directly via IOKit. It ships two
front-ends over one shared sensor core:

- a **CLI** (`macthermal`) — summary, `--all`, `--json`, `--watch` dashboard;
- a **menu-bar app** (`macthermal.app`) — SwiftUI `MenuBarExtra` agent.

Pure Swift compiled with `swiftc` (no SwiftPM/Xcode project). Targets macOS 13+,
Apple Silicon and Intel.

## Build / test / run

```sh
make            # CLI       -> ./macthermal
make gui        # menu-bar  -> ./macthermal.app (ad-hoc signed, LSUIElement)
make open       # build the app and launch it
make test       # pure-logic test suite — NO SMC hardware needed (CI-friendly)
make run        # build + run the CLI
make watch      # build + run the live dashboard (1s)
make install    # copy CLI to $(PREFIX)/bin   (PREFIX defaults to /usr/local)
make clean
```

Requires the Xcode command-line tools (`xcode-select --install`). `make` is
timestamp-driven: a no-op build prints "Nothing to be done" — that's expected,
not an error. **Always run `make test` after touching `Sources/`** — it's fast
and needs no hardware.

## Source layout

| File | Role |
|------|------|
| `Sources/SMC.swift` | Low-level IOKit layer: the `SMC` class, `SMCValue` decoding, key enumeration + per-connection caches. The ABI-sensitive code. |
| `Sources/Sensors.swift` | **Shared core, UI-agnostic.** Model (`TempReading`, `FanReading`, `ThermalState`, `Snapshot`), `Severity`, threshold functions (`tempLevel`/`fanLevel`), `categorize`, collection (`collectTemps`/`collectFans`). |
| `Sources/JSONReport.swift` | `Codable`-based JSON encoder (`renderJSON`), shared by CLI and tests. |
| `Sources/main.swift` | CLI only: arg parsing, ANSI `Palette`, text rendering, entry point. Has top-level code, so it's named `main.swift`. |
| `Sources/gui/MenuBarApp.swift` | GUI only: `SMCReader` actor, `ThermalMonitor` (`@MainActor` `ObservableObject`), SwiftUI views, `@main`. |
| `Tests/Tests.swift` | Standalone test runner (`@main`), no XCTest. |
| `Resources/Info.plist` | App bundle plist (`LSUIElement`, bundle id, exec name). |

The three build targets are just different file sets over the shared core —
see `Makefile`: `SHARED`, `CLI_SRC`, `GUI_SRC`, `TEST_SRC`.

## Architecture rules

- **One source of truth.** Sensor reading, thresholds, categorization, and the
  data model live in `Sensors.swift`. CLI and GUI must consume it, not
  reimplement it. The CLI maps `Severity` → ANSI (`Palette.paint`); the GUI maps
  `Severity` → SwiftUI `Color` (`Severity.color` in `MenuBarApp.swift`). Don't
  push color/formatting concerns down into the sensor layer.
- **GUI concurrency.** The IOKit connection is non-`Sendable` and lives inside
  the `SMCReader` **actor**, so every read runs off the main thread; only the
  immutable, `Sendable` `Snapshot` crosses back to `@MainActor`. Do not access
  `SMC` from the main actor or a bare `DispatchQueue` closure — that
  reintroduces the data race we deliberately removed.

## Non-obvious gotchas (read before editing the relevant file)

- **SMCParamStruct is exactly 80 bytes** (`SMC.swift`). Swift collapses the
  trailing padding of nested C structs (→ 76 bytes), which makes the IOKit call
  fail with `kIOReturnBadArgument`. The struct is therefore **flattened with
  explicit `*Pad*` fields** to reproduce the C ABI (`pLimit@12`, `result@40`,
  `data32@44`, `bytes@48`). If you touch it, the offsets must not move — verify
  with `MemoryLayout<SMCParamStruct>.stride == 80`.
- **`String(format: "%-9@", x)` does NOT pad on Apple platforms** — the field
  width on `%@` is silently ignored. Use the `pad(_:_:)` helper in `main.swift`
  for column alignment, never `%@` width.
- **Caching.** `SMC` caches the key list and each key's type/size for the life
  of the connection (neither changes at runtime). `collectTemps` reads via
  `smc.temperatureKeys()` (cached filtered set), so refreshes only read live
  values — ~25× faster, which matters for `--watch` and the menu-bar app. Don't
  re-enumerate all keys per refresh.
- **Temperature filtering.** Keep `T…` keys of type `flt `/`sp78` whose value is
  in a plausible `1–130 °C` range (drops spurious/zero sensors).
- **`categorize` is intentionally case-sensitive** — SMC key naming is
  (`Tp`=P-core, `Te`=E-core, `Tg`/`TG`=GPU, `TB`=battery, `Tm`/`TM`=memory).
- **`SMCValue.decode` is split into typed statements on purpose.** Keep the
  per-byte reads (`u16be`/`u32be`/`fltLE`) and the divisor lookup as separate,
  explicitly-typed steps. Collapsing them into one inline `|`/`<<` shift-chain or
  a big ternary `switch` triggers "unable to type-check this expression in
  reasonable time" — don't let a formatter re-inline it.

## Naming

The binary/formula is `macthermal`, **not** `thermal`: macOS already ships
`/usr/bin/thermal` (`com.apple.thermal`, a thermal-pressure simulation tool).
Never name the product, install path, or formula `thermal` — it would shadow a
system binary and be rejected by Homebrew.

## Conventions

- Match the surrounding style: terse, comment the *why* (especially ABI/format
  gotchas), not the obvious.
- Status thresholds are heuristics, not vendor specs — if you change them,
  update both `Sensors.swift` and the README table, and the threshold tests.
- Add a test in `Tests/Tests.swift` for any new pure logic (decoding,
  thresholds, categorization, JSON). Tests must not require a live SMC.
- Don't commit build artifacts: `macthermal`, `macthermal-gui`, `macthermal.app`
  are gitignored.

## Common tasks

- **Add a sensor category:** extend `Category` (it's `CaseIterable`; rendering
  iterates `Category.allCases`) and the `categorize` switch; add a test.
- **Add a friendly sensor label:** add to `knownLabels` in `Sensors.swift`.
- **Change JSON shape:** edit `JSONReport.swift` (Codable types) and update the
  JSON test assertions.
