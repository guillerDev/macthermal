# macthermal

A dependency-free macOS **CLI** and **menu-bar app** that read **temperature**
and **fan speed** straight from the System Management Controller (SMC) via
IOKit — then analyze them (grouping, hotspot detection, fan utilization, and a
plain-English verdict).

Works on both **Apple Silicon** (M-series, hundreds of on-die sensors) and
**Intel** Macs. No `sudo`, no third-party libraries.

> Contributing or using an AI assistant on this repo? See [AGENTS.md](AGENTS.md)
> for build/test commands, architecture, and the non-obvious gotchas.

## Install

Via the Homebrew tap:

```sh
brew install guillerDev/tap/macthermal            # CLI
brew install --cask guillerDev/tap/macthermal     # menu-bar app
```

The menu-bar app is ad-hoc signed (not notarized), so on first launch macOS
Gatekeeper will block it. Approve it once by right-clicking the app in Finder
and choosing **Open**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/macthermal.app"
```

Prefer building from source? See **[Build](#build)** below.

## Build

```sh
make            # CLI  -> ./macthermal
make gui        # GUI  -> ./macthermal.app (menu-bar app)
make open       # build the app and launch it
make test       # run the pure-logic test suite (no SMC hardware needed)
make install    # copy the CLI to /usr/local/bin (PREFIX=... to change)
```

Requires the Xcode command-line tools (`xcode-select --install`).

You can also build the CLI/tests with SwiftPM (`swift build`, `swift run
macthermal`) or open `Package.swift` in Xcode. The menu-bar `.app` is built only
by `make gui`. See **[docs/BUILDING.md](docs/BUILDING.md)** for all three build
paths and when to use each.

## Usage

```sh
macthermal                 # grouped summary + assessment
macthermal --all           # every individual temperature sensor
macthermal --watch 1       # live dashboard, refresh every 1s (Ctrl-C to quit)
macthermal --json | jq .   # machine-readable output
macthermal --help
```

### Example

```
TEMPERATURE
  CPU      65.8°C  avg 54.2°C · 49 sensors · normal
  GPU      56.9°C  avg 51.9°C · 4 sensors · cool
  Memory   49.0°C  avg 47.2°C · 7 sensors · cool
  Battery  35.8°C  avg 35.8°C · 3 sensors · cool
  ─ hotspot 65.8°C at TCMz · overall avg 45.6°C · normal

FANS
  Fan 1   2317 rpm [████············]  24% · 1200–5779 rpm · low
  Fan 2   2515 rpm [████············]  26% · 1200–6241 rpm · low

All temperatures nominal. System is cool and idle-to-light.
```

Fanless Macs (e.g. MacBook Air) report no fans, which is expected.

## Menu-bar app

`make gui` builds `macthermal.app` — a lightweight menu-bar agent (`LSUIElement`,
no Dock icon) that shows the hottest temperature next to a thermometer icon in
the menu bar and refreshes every few seconds. Clicking it opens a panel with:

- the OS thermal-pressure state (color-coded dot),
- the hottest temperature per component (CPU / GPU / memory / battery / …),
- per-fan RPM with a utilization bar,
- the overall hotspot,
- the °C/°F unit toggle and an **Open at Login** checkbox, plus Refresh / Quit.

The **Open at Login** checkbox registers the app as a login item via the modern
`SMAppService` API (macOS 13+) — no helper bundle, nothing to configure by hand.

It shares the exact same SMC reader as the CLI (`Sources/Sensors.swift`); the
IOKit connection is isolated in an `actor` so all sensor reads happen off the
main thread and only immutable snapshots reach SwiftUI.

```sh
make open          # build + launch
# to run at login: open the panel and tick "Open at Login"
```

The app is ad-hoc code-signed during the build so it runs locally on Apple
Silicon without a developer certificate.

## How it works

- Opens the `AppleSMC` IOKit service and calls it with the kernel's
  `SMCParamStruct` ABI (`Sources/SMC.swift`).
- Enumerates every SMC key (`#KEY` → indexed reads), keeps the temperature
  sensors (`T…` keys, `flt`/`sp78` types, plausible 1–130 °C range), and reads
  the fan block (`FNum`, `F<i>Ac/Mn/Mx/Tg`).
- Decodes the SMC fixed-point / float encodings, then categorizes sensors by
  key prefix (`Tp`/`Te` cores, `Tg` GPU, `TB` battery, …) for the summary.
- Caches the key list and each key's type/size for the life of the SMC
  connection (neither changes at runtime). The first capture enumerates every
  key (~2,300 on Apple Silicon); every refresh after that reads only the known
  sensor values — roughly a **25× speedup**, which matters for the menu-bar app
  and `--watch`, both of which refresh continuously.

### Note on the struct layout

The kernel's `SMCParamStruct` is exactly **80 bytes**. Swift collapses the
trailing padding of nested C structs (yielding 76 bytes), which makes the
IOKit call fail with `kIOReturnBadArgument`. `SMC.swift` therefore uses a
**flattened struct with explicit padding fields** to reproduce the C ABI
(`pLimit@12`, `result@40`, `data32@44`, `bytes@48`).

## Thresholds

| Temperature | Status   | Fan utilization | Status   |
|-------------|----------|-----------------|----------|
| < 60 °C     | cool     | < 5 %           | idle     |
| < 78 °C     | normal   | < 50 %          | low      |
| < 90 °C     | warm     | < 85 %          | elevated |
| < 100 °C    | hot      | ≥ 85 %          | maxing   |
| ≥ 100 °C    | critical |                 |          |

These are heuristics for a quick health read, not vendor-spec throttle points.

## Releasing

Cutting a release is just pushing a version tag; CI builds, publishes a GitHub
Release, and updates the Homebrew tap. See **[docs/RELEASING.md](docs/RELEASING.md)**
for the full process and the one-time tap-token setup.
