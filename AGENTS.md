# AGENTS.md

Guidance for AI agents (and humans) working in this repo. Keep it current when
you change the build, the architecture, or a non-obvious convention.

## What this is

`macthermal` is a dependency-free macOS temperature & fan-speed analyzer that
reads the System Management Controller (SMC) directly via IOKit. It ships two
front-ends over one shared sensor core:

- a **CLI** (`macthermal`) — summary, `--all`, `--json`, `--watch` dashboard;
- a **native diagnostic app** (`MacThermal.app`) — SwiftUI `MenuBarExtra` plus
  a dashboard for history, alerts, process correlation, comparisons, reports,
  and incident recording.

Pure Swift. The **`Makefile` + `swiftc` is the source of truth** for builds,
tests, releases, and Homebrew. A `Package.swift` is committed **only** as an
editor/IDE convenience (open in Xcode, autocomplete, `swift build`/`swift run`,
and to give SourceKit-LSP a whole-module view) — it does not drive releases and
SwiftPM cannot produce the menu-bar `.app` bundle (that stays `make gui`). Both
build systems compile the same files; see the dual-build gotcha below for how one
source tree satisfies both. Targets macOS 13+, Apple Silicon and Intel.

## Build / test / run

```sh
make            # CLI       -> ./macthermal
make gui        # menu-bar  -> ./MacThermal.app (ad-hoc signed, LSUIElement)
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

To work in Xcode, open `Package.swift` (**not** the folder — that gives a bare
file browser) — no generated project. `swift build`, `swift run macthermal
[args]`, and `swift run macthermalTests` all work. **The `.app` is not a SwiftPM
product** — build/run the menu-bar app with `make gui` / `make open`. After
changing `Sources/`, run **both** `make test` and `swift build` so neither build
path silently breaks (they compile the same files differently — see the
module-bridging gotcha).

All three build paths (Makefile, SwiftPM, Xcode) are documented in
[docs/BUILDING.md](docs/BUILDING.md), including a capability matrix and which to
use when.

## Source layout

Files are grouped into per-target directories so SwiftPM can model each build
target as a module (SwiftPM forbids one file belonging to two targets). The
Makefile collects core and GUI files with scoped wildcards, so a newly split
SwiftUI view automatically joins the flat build.

| File | Role |
|------|------|
| `Sources/MacThermalCore/SMC.swift` | Low-level IOKit layer: the `SMC` class, `SMCValue` decoding, key enumeration + per-connection caches. The ABI-sensitive code. |
| `Sources/MacThermalCore/Sensors.swift` | **Shared core, UI-agnostic.** Model (`TempReading`, `FanReading`, `ThermalState`, `Snapshot`), `Severity`, threshold functions (`tempLevel`/`fanLevel`), `categorize`, collection (`collectTemps`/`collectFans`). |
| `Sources/MacThermalCore/Thermal*.swift`, `Process*.swift` | Persistable history/incident models, summaries, comparisons, throttling assessment, alerts, and process/temperature correlation. Pure logic belongs here and is tested without live hardware. |
| `Sources/MacThermalCore/JSONReport.swift` | `Codable`-based JSON encoder (`renderJSON`), shared by CLI and tests. |
| `Sources/MacThermalCore/DiagnosticReportRenderer.swift` | Dependency-free HTML and CSV diagnostic report rendering. |
| `Sources/macthermal/main.swift` | CLI only: arg parsing, ANSI `Palette`, text rendering, entry point. Has top-level code, so it's named `main.swift`. |
| `Sources/macthermal-gui/MenuBarApp.swift` | GUI composition root and `@main`; individual views, actors, settings, persistence, and monitoring each live in dedicated files beside it. |
| `Sources/macthermal-gui/ThermalMonitor.swift` | Main-actor presentation state and polling orchestration. It coordinates the isolated SMC/process/history/notification actors. |
| `Sources/macthermal-gui/Thermal*State.swift`, `IncidentRecordingState.swift`, `AppStatusState.swift` | Narrow SwiftUI observation domains for live readings, stored diagnostics, two-second recording progress, and app integration. Historical screens must not observe the live sensor or incident-counter paths. |
| `Sources/macthermal-gui/HistoryStore.swift` | Local NDJSON history, bounded JSON incident persistence, and the recoverable active-incident NDJSON journal under Application Support. |
| `Tests/Tests.swift` | Standalone test runner (`@main`), no XCTest. |
| `Package.swift` | SwiftPM manifest (editor/IDE convenience only — see "What this is"). Core is target `MacThermalCore`; `macthermal`, `macthermal-gui`, `macthermalTests` depend on it. |
| `Resources/Info.plist` | App bundle plist (`LSUIElement`, bundle id, exec name, `CFBundleIconFile`). |
| `Resources/AppIcon.icns` | App icon (committed). Regenerate with `make icon`. |
| `scripts/AppIconGen.swift`, `scripts/make-icon.sh` | Generate `AppIcon.icns` from the SF Symbols thermometer; only needed when changing the icon. |

The three build targets are just different file sets over the shared core —
see `Makefile`: `SHARED`, `CLI_SRC`, `GUI_SRC`, `TEST_SRC`.

## Architecture rules

- **One source of truth.** Sensor reading, thresholds, categorization, and the
  data model live in `Sensors.swift`. CLI and GUI must consume it, not
  reimplement it. The CLI maps `Severity` → ANSI (`Palette.paint`); the GUI maps
  `Severity` → SwiftUI `Color` (`Severity.color` in `SeverityColor.swift`). Don't
  push color/formatting concerns down into the sensor layer.
- **GUI concurrency.** The IOKit connection is non-`Sendable` and lives inside
  the `SMCReader` **actor**, so every read runs off the main thread; only the
  immutable, `Sendable` `Snapshot` crosses back to `@MainActor`. Do not access
  `SMC` from the main actor or a bare `DispatchQueue` closure — that
  reintroduces the data race we deliberately removed.
- **Adaptive polling.** `ThermalMonitor` uses one-shot timers at utility priority:
  nine seconds in the background, three while the panel/dashboard is visible,
  and two during elevated heat or incident recording. Keep visibility signals
  wired through the views; dashboard visibility comes from
  `WindowVisibilityObserver` because SwiftUI can keep a closed Window scene
  mounted. Do not restore a fixed repeating timer or rely only on `onAppear`.
- **Narrow UI observation.** `ThermalMonitor` coordinates work, while
  `ThermalLiveState`, `ThermalArchiveState`, `IncidentRecordingState`, and
  `AppStatusState` publish to SwiftUI independently. Do not collapse these back
  into one frequently changing object: history charts and analytics should not
  invalidate on every sensor refresh or two-second incident counter update.
- **History is append-only NDJSON.** `HistoryStore` appends one independent JSON
  sample and compacts it at most daily according to retention. Loading and
  compaction stream lines instead of materializing the encoded file. Keep
  decoding tolerant of a truncated last line so a crash cannot invalidate
  earlier data. `ThermalSample.categoryAverages` is optional because samples
  recorded before component-average charts only contain `categoryPeaks`; do not
  make that field required without a storage migration.
- **Incident cadence stays separate.** General history always follows the user's
  15/30/60-second interval. Two-second samples recorded during an incident go to
  `active-incident.ndjson` and the bounded incident segment only; mixing them
  into general history biases averages, pressure rates, and comparisons.
- **Bound long-lived storage.** The UI retains at most the latest 14 days in
  memory (enough for two seven-day comparison periods), while disk retention can
  remain longer. Active incidents are journaled incrementally, split at the
  configured duration, and pruned by age/count after finalization.
- **Comparison semantics live in the core.** `ThermalComparisonAssessment`
  applies noise tolerances and can report improved, regressed, mixed, or
  unchanged results. Fan effort is contextual rather than inherently good or
  bad, and an absent fan sensor must be presented as unavailable rather than
  zero load.
- **Automatic capture is independent from notifications.** Its master switch
  controls only automatic incidents; manual recording remains available and
  shared temperature-detection rules stay editable when notifications are off.
- **Correlation is not causation.** `ThermalAnalytics` correlates sampled CPU
  percentages with hotspot temperature. UI and reports must keep the disclaimer;
  never label a process as the definitive cause of heat.

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
- **One source tree, two build systems (module bridging).** The flat `swiftc`
  build compiles each target as **one module** (shared files recompiled in); SwiftPM
  compiles the shared code as a separate **`MacThermalCore` module** the front-ends
  import. To satisfy both, the core's cross-target API is `public`, and each entry
  CLI/tests and each GUI file that consumes core symbols import the core behind
  `#if canImport(MacThermalCore)` — false in the flat build (no such module, symbols
  already in scope), true under SwiftPM/Xcode. Keep new cross-target symbols `public`
  and this guard in place, or one of the two builds breaks.
- **`Category` collides with AppKit's ObjC `Category` typedef under SwiftPM.** GUI
  code that needs the type uses the guarded `ThermalCategory` alias in
  `TempGroup.swift`; avoid introducing bare `Category` in AppKit-importing files.
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
- Don't commit build artifacts: `macthermal`, `macthermal-gui`, `MacThermal.app`
  are gitignored.

## Common tasks

- **Add a sensor category:** extend `Category` (it's `CaseIterable`; rendering
  iterates `Category.allCases`) and the `categorize` switch; add a test.
- **Add a friendly sensor label:** add to `knownLabels` in `Sensors.swift`.
- **Change JSON shape:** edit `JSONReport.swift` (Codable types) and update the
  JSON test assertions.
