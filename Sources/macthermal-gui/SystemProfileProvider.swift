import Darwin
import Foundation
#if canImport(MacThermalCore)
import MacThermalCore
#endif

enum SystemProfileProvider {
    static func current() -> DiagnosticContext {
        let processInfo = ProcessInfo.processInfo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"

        return DiagnosticContext(
            hardwareModel: sysctlString("hw.model") ?? "Unknown Mac",
            operatingSystem: processInfo.operatingSystemVersionString,
            architecture: architecture,
            processorCount: processInfo.processorCount,
            physicalMemoryBytes: processInfo.physicalMemory,
            appVersion: version
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(cString: value)
    }
}
