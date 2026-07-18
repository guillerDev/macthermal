import SwiftUI

/// `SMAppService` is a synchronous daemon-backed API, so this small adapter
/// turns the monitor's optimistic setter into the binding Toggle requires.
/// Keeping it out of larger view bodies also confines the integration binding.
struct LaunchAtLoginToggle: View {
    let monitor: ThermalMonitor
    @EnvironmentObject private var status: AppStatusState

    var body: some View {
        Toggle("Open at Login", isOn: launchAtLogin)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { status.launchAtLogin },
            set: { enabled in monitor.setLaunchAtLogin(enabled) }
        )
    }
}
