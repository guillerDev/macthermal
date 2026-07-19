import Foundation

/// App version, read from the bundle's `CFBundleShortVersionString`. The Makefile
/// stamps this from the git tag at build time (see AGENTS.md / the release skill),
/// so a released build reports the exact tag (e.g. `0.5.1`) and a local `make gui`
/// build reports its `git describe` version (e.g. `0.5.1-3-gabc123-dirty`).
enum AppInfo {
    /// Raw stamped version, or `"development"` when the key is unset (e.g. a build
    /// made without git and without an `APP_VERSION` override).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    /// Version for display: `v`-prefixed for real versions, left as-is for the
    /// `"development"` fallback (so it never reads `vdevelopment`).
    static var displayVersion: String {
        let v = version
        return v == "development" ? v : "v\(v)"
    }
}
