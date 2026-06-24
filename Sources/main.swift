import Foundation

// MARK: - CLI options

struct Options {
    var json = false
    var showAll = false
    var watch: Double? = nil
    var color = true
    var help = false
}

func parseArgs(_ args: [String]) -> Options {
    var o = Options()
    if isatty(fileno(stdout)) == 0 { o.color = false }
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--json", "-j": o.json = true
        case "--all", "-a": o.showAll = true
        case "--no-color": o.color = false
        case "--help", "-h": o.help = true
        case "--watch", "-w":
            var interval = 2.0
            if i + 1 < args.count, let v = Double(args[i + 1]) { interval = v; i += 1 }
            o.watch = max(0.25, interval)
        default:
            FileHandle.standardError.write("warning: unknown option '\(args[i])'\n".data(using: .utf8)!)
        }
        i += 1
    }
    return o
}

// MARK: - ANSI color

struct Palette {
    let on: Bool
    func c(_ code: String, _ s: String) -> String { on ? "\u{1b}[\(code)m\(s)\u{1b}[0m" : s }
    func dim(_ s: String) -> String { c("2", s) }
    func bold(_ s: String) -> String { c("1", s) }
    func green(_ s: String) -> String { c("32", s) }
    func yellow(_ s: String) -> String { c("33", s) }
    func red(_ s: String) -> String { c("31", s) }
    func cyan(_ s: String) -> String { c("36", s) }

    /// Maps a UI-agnostic severity onto an ANSI color.
    func paint(_ severity: Severity, _ s: String) -> String {
        switch severity {
        case .ok, .normal: return green(s)
        case .warn:        return yellow(s)
        case .hot, .critical: return red(s)
        }
    }
}

// MARK: - Rendering

func renderHuman(temps: [TempReading], fans: [FanReading], opts: Options) -> String {
    let p = Palette(on: opts.color)
    var lines: [String] = []

    // OS thermal pressure (supported on Apple Silicon; legacy pmset levels are not)
    let state = ThermalState.current()
    lines.append(p.bold("THERMAL STATE") + "  " + p.paint(state.severity, state.name) + "  " + p.dim("· " + state.note))
    lines.append("")

    // Temperatures
    lines.append(p.bold("TEMPERATURE"))
    if temps.isEmpty {
        lines.append("  " + p.dim("no temperature sensors readable"))
    } else {
        if opts.showAll {
            for t in temps {
                let (st, sev) = tempLevel(t.celsius)
                let val = p.paint(sev, String(format: "%6.1f°C", t.celsius))
                lines.append(String(format: "  %-6@ %@  %@ %@",
                                    t.key as NSString, val, p.dim(st), p.dim("· " + t.label)))
            }
        } else {
            // Group: show hottest per category
            for cat in Category.allCases {
                let group = temps.filter { $0.category == cat }
                guard !group.isEmpty else { continue }
                let hottest = group.first!
                let avg = group.map { $0.celsius }.reduce(0, +) / Double(group.count)
                let (st, sev) = tempLevel(hottest.celsius)
                let val = p.paint(sev, String(format: "%5.1f°C", hottest.celsius))
                let detail = p.dim(String(format: "avg %.1f°C · %d sensors · %@",
                                          avg, group.count, st))
                lines.append(String(format: "  %-9@ %@  %@", cat.rawValue as NSString, val, detail))
            }
        }
        let hottest = temps.first!
        let avg = temps.map { $0.celsius }.reduce(0, +) / Double(temps.count)
        let (st, sev) = tempLevel(hottest.celsius)
        lines.append("  " + p.dim(String(format: "─ hotspot %@ at ", p.paint(sev, String(format: "%.1f°C", hottest.celsius)))
                                  + "\(hottest.label) (\(hottest.key)) · overall avg \(String(format: "%.1f°C", avg)) · \(st)"))
    }

    lines.append("")

    // Fans
    lines.append(p.bold("FANS"))
    if fans.isEmpty {
        lines.append("  " + p.dim("no fans detected (fanless or sensors unavailable)"))
    } else {
        for f in fans {
            let (st, sev) = fanLevel(f.utilization)
            let bar = barGraph(f.utilization, width: 16, palette: p)
            let rpm = p.paint(sev, String(format: "%5.0f rpm", f.rpm))
            let detail = p.dim(String(format: "%3.0f%% · %.0f–%.0f rpm · %@",
                                      f.utilization, f.min, f.max, st))
            lines.append(String(format: "  Fan %d  %@ %@ %@", f.index + 1, rpm, bar, detail))
        }
    }

    lines.append("")
    lines.append(p.dim(verdict(temps: temps, fans: fans)))
    return lines.joined(separator: "\n")
}

func barGraph(_ pct: Double, width: Int, palette p: Palette) -> String {
    let filled = Int((pct / 100.0 * Double(width)).rounded())
    let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
    let colored: String
    switch pct {
    case ..<50: colored = p.green(bar)
    case ..<85: colored = p.yellow(bar)
    default:    colored = p.red(bar)
    }
    return "[\(colored)]"
}

func verdict(temps: [TempReading], fans: [FanReading]) -> String {
    let hottest = temps.map { $0.celsius }.max() ?? 0
    let fanUtil = fans.map { $0.utilization }.max() ?? 0
    if hottest >= 100 { return "⚠️  System is running critically hot — check workload and ventilation." }
    if hottest >= 90 { return "Running hot under load. Fans are responding; this is normal for sustained heavy tasks." }
    if hottest >= 78 {
        return fanUtil > 60
            ? "Warm and actively cooling — typical under moderate-to-heavy load."
            : "Warm but fans still have headroom. Healthy."
    }
    return "All temperatures nominal. System is cool and idle-to-light."
}

func renderJSON(temps: [TempReading], fans: [FanReading]) -> String {
    func obj(_ pairs: [(String, Any)]) -> String {
        "{" + pairs.map { k, v in
            let val: String
            switch v {
            case let s as String: val = "\"\(s)\""
            case let d as Double: val = String(format: "%.2f", d)
            case let i as Int: val = "\(i)"
            default: val = "null"
            }
            return "\"\(k)\":\(val)"
        }.joined(separator: ",") + "}"
    }
    let tj = temps.map { obj([("key", $0.key), ("label", $0.label), ("category", $0.category.rawValue), ("celsius", $0.celsius)]) }
    let fj = fans.map { obj([("fan", $0.index + 1), ("rpm", $0.rpm), ("min", $0.min), ("max", $0.max), ("target", $0.target), ("utilization", $0.utilization)]) }
    let hottest = temps.map { $0.celsius }.max() ?? 0
    let avg = temps.isEmpty ? 0 : temps.map { $0.celsius }.reduce(0, +) / Double(temps.count)
    let summary = obj([("thermalState", ThermalState.current().name), ("hottestC", hottest), ("averageC", avg), ("sensorCount", temps.count), ("fanCount", fans.count)])
    return "{\"summary\":\(summary),\"temperatures\":[\(tj.joined(separator: ","))],\"fans\":[\(fj.joined(separator: ","))]}"
}

// MARK: - Help

let helpText = """
macthermal — macOS temperature & fan analyzer (reads the SMC directly via IOKit)

USAGE:
  macthermal [options]

OPTIONS:
  -a, --all          List every individual sensor instead of grouped summary
  -j, --json         Emit machine-readable JSON
  -w, --watch [sec]  Refresh continuously (default 2s); Ctrl-C to stop
      --no-color     Disable ANSI colors
  -h, --help         Show this help

EXAMPLES:
  macthermal                 # grouped summary + assessment
  macthermal --all           # every temperature sensor
  macthermal --watch 1       # live dashboard, 1s refresh
  macthermal --json | jq .   # pipe to other tools

There is also a menu-bar GUI — build it with `make gui`, then `open macthermal.app`.
"""

// MARK: - Entry point

func runOnce(_ smc: SMC, _ opts: Options) {
    let temps = collectTemps(smc)
    let fans = collectFans(smc)
    if opts.json {
        print(renderJSON(temps: temps, fans: fans))
    } else {
        print(renderHuman(temps: temps, fans: fans, opts: opts))
    }
}

let opts = parseArgs(Array(CommandLine.arguments.dropFirst()))

if opts.help {
    print(helpText)
    exit(0)
}

let smc: SMC
do {
    smc = try SMC()
} catch {
    FileHandle.standardError.write("macthermal: \(error)\n".data(using: .utf8)!)
    exit(1)
}

if let interval = opts.watch {
    // Hide cursor, restore on exit.
    let sigHandler: @convention(c) (Int32) -> Void = { _ in
        print("\u{1b}[?25h", terminator: "")  // show cursor
        exit(0)
    }
    signal(SIGINT, sigHandler)
    signal(SIGTERM, sigHandler)

    let p = Palette(on: opts.color)
    print("\u{1b}[?25l", terminator: "")  // hide cursor
    print("\u{1b}[2J", terminator: "")     // one full clear, only at startup
    let fmt = ISO8601DateFormatter()

    while true {
        let ts = fmt.string(from: Date())
        var frame = p.dim("macthermal · live · \(ts) · Ctrl-C to quit") + "\n\n"
        frame += opts.json
            ? renderJSON(temps: collectTemps(smc), fans: collectFans(smc))
            : renderHuman(temps: collectTemps(smc), fans: collectFans(smc), opts: opts)

        // Flicker-free repaint: home, then overwrite each line clearing only to
        // end-of-line, then clear anything left below from a taller prior frame.
        // Built as one string and written in a single syscall.
        var out = "\u{1b}[H"
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            out += String(line) + "\u{1b}[K\n"
        }
        out += "\u{1b}[J"
        FileHandle.standardOutput.write(out.data(using: .utf8)!)

        Thread.sleep(forTimeInterval: interval)
    }
} else {
    runOnce(smc, opts)
}
