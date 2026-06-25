import Foundation
import IOKit

// MARK: - SMC low-level interface
//
// Talks to the AppleSMC IOKit service the same way Apple's own tools do.
// The struct layout below mirrors the kernel's SMCParamStruct ABI exactly;
// changing field order/size will break IOConnectCallStructMethod.

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_INDEX: UInt8 = 8

/// 32-byte payload buffer, imported to match the C `SMCBytes_t` tuple ABI.
typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

/// Flattened mirror of the kernel's `SMCKeyData_t` (a.k.a. SMCParamStruct).
///
/// IMPORTANT: this MUST be exactly 80 bytes with the field offsets below.
/// Swift collapses the trailing/inter-struct padding of nested C structs, so
/// the nesting is flattened and explicit `*Pad*` fields re-create the C ABI:
///   key@0, vers@4, pLimit@12, keyInfo@28, result@40, data32@44, bytes@48.
private struct SMCParamStruct {
    var key: UInt32 = 0                  // 0
    var versMajor: UInt8 = 0             // 4
    var versMinor: UInt8 = 0             // 5
    var versBuild: UInt8 = 0             // 6
    var versReserved: UInt8 = 0          // 7
    var versRelease: UInt16 = 0          // 8
    var versPad: UInt16 = 0              // 10  → push pLimit to 12
    var pLimitVersion: UInt16 = 0        // 12
    var pLimitLength: UInt16 = 0         // 14
    var pLimitCpu: UInt32 = 0            // 16
    var pLimitGpu: UInt32 = 0            // 20
    var pLimitMem: UInt32 = 0            // 24
    var keyInfoDataSize: UInt32 = 0      // 28
    var keyInfoDataType: UInt32 = 0      // 32
    var keyInfoDataAttributes: UInt8 = 0 // 36
    var keyInfoPad0: UInt8 = 0           // 37
    var keyInfoPad1: UInt8 = 0           // 38
    var keyInfoPad2: UInt8 = 0           // 39  → push result to 40
    var result: UInt8 = 0                // 40
    var status: UInt8 = 0                // 41
    var data8: UInt8 = 0                 // 42
    var dataPad: UInt8 = 0               // 43  → push data32 to 44
    var data32: UInt32 = 0               // 44
    var bytes: SMCBytes = (              // 48 → 80
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// A decoded value read from a single SMC key.
struct SMCValue {
    let key: String
    let type: String
    let size: UInt32
    let bytes: SMCBytes

    /// Interprets the raw bytes according to the SMC data-type code.
    /// Handles the float/fixed-point encodings used for temperature and fans.
    var double: Double? {
        var b = bytes
        return withUnsafeBytes(of: &b) { raw -> Double? in
            let p = raw.bindMemory(to: UInt8.self)
            // Each case checks `size` against the bytes it reads. The backing
            // buffer is always a 32-byte (zero-padded) tuple, so this is not
            // about memory safety — it's about not fabricating a value from
            // bytes a short/misreported key never actually provided.
            switch type {
            case "flt ":
                guard size >= 4 else { return nil }
                let bits = UInt32(p[0]) | UInt32(p[1]) << 8 | UInt32(p[2]) << 16 | UInt32(p[3]) << 24
                return Double(Float(bitPattern: bits))
            case "ui8 ", "ui8":
                guard size >= 1 else { return nil }
                return Double(p[0])
            case "ui16":
                guard size >= 2 else { return nil }
                return Double(UInt16(p[0]) << 8 | UInt16(p[1]))
            case "ui32":
                guard size >= 4 else { return nil }
                return Double(UInt32(p[0]) << 24 | UInt32(p[1]) << 16 | UInt32(p[2]) << 8 | UInt32(p[3]))
            case "si8 ", "si8":
                guard size >= 1 else { return nil }
                return Double(Int8(bitPattern: p[0]))
            case "si16":
                guard size >= 2 else { return nil }
                return Double(Int16(bitPattern: UInt16(p[0]) << 8 | UInt16(p[1])))
            case "sp78":
                guard size >= 2 else { return nil }
                let v = Int16(bitPattern: UInt16(p[0]) << 8 | UInt16(p[1]))
                return Double(v) / 256.0
            case "fpe2":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 4.0
            case "fp2e":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 16384.0
            case "fp1f":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 32768.0
            case "fp4c":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 4096.0
            case "fp5b":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 2048.0
            case "fp6a":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 1024.0
            case "fp79":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 512.0
            case "fp88":
                guard size >= 2 else { return nil }
                let v = UInt16(p[0]) << 8 | UInt16(p[1])
                return Double(v) / 256.0
            default:
                return nil
            }
        }
    }
}

enum SMCError: Error, CustomStringConvertible {
    case driverNotFound
    case failedToOpen(kern_return_t)
    case callFailed(kern_return_t)

    var description: String {
        switch self {
        case .driverNotFound:
            return "AppleSMC service not found (is this macOS?)"
        case .failedToOpen(let r):
            return "could not open SMC connection (kern_return 0x\(String(r, radix: 16)))"
        case .callFailed(let r):
            return "SMC call failed (kern_return 0x\(String(r, radix: 16)))"
        }
    }
}

final class SMC {
    private var connection: io_connect_t = 0

    // Per-connection caches. The SMC key set, and each key's type/size, are
    // fixed for the life of the connection — they never change at runtime — so
    // we read them once and reuse them. This turns every *repeat* capture (the
    // menu-bar app refreshes every few seconds; `--watch` every second) from a
    // full ~2,300-key re-enumeration into a handful of value reads.
    private var keyListCache: [String]?
    private var keyInfoCache: [String: (type: String, size: UInt32)] = [:]
    private var tempKeyCache: [String]?
    // Fan count and per-fan min/max RPM are hardware limits — fixed at runtime,
    // so they are read once and cached too. Only the live RPM (`Ac`) and target
    // (`Tg`) are re-read each capture.
    private var fanCountCache: Int?
    private var fanLimitsCache: [Int: (min: Double, max: Double)] = [:]

    init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.failedToOpen(result) }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private func call(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let inSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection, KERNEL_INDEX_SMC, &input, inSize, &output, &outSize)
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
        return output
    }

    /// Number of keys the SMC exposes (read via the "#KEY" meta key). Clamped
    /// to a sane range so a corrupt/garbage count can't blow up the enumeration
    /// (huge `reserveCapacity`, millions of IOKit calls, or an `Int(_:)` trap).
    func keyCount() throws -> UInt32 {
        let raw = try read("#KEY").double ?? 0
        return UInt32(clampedCount(raw, upperBound: 8192))
    }

    /// Returns the FourCharCode key name at a given enumeration index.
    func key(at index: UInt32) throws -> String {
        var input = SMCParamStruct()
        input.data8 = SMC_CMD_READ_INDEX
        input.data32 = index
        let out = try call(&input)
        return fourCharString(out.key)
    }

    /// Reads a key's type and size (the SMC "key info" command). Cached: a
    /// key's metadata never changes, so this is a one-time cost per key.
    private func info(for key: String) throws -> (type: String, size: UInt32) {
        if let cached = keyInfoCache[key] { return cached }
        var info = SMCParamStruct()
        info.key = fourCharCode(key)
        info.data8 = SMC_CMD_READ_KEYINFO
        let out = try call(&info)
        let meta = (type: fourCharString(out.keyInfoDataType), size: out.keyInfoDataSize)
        keyInfoCache[key] = meta
        return meta
    }

    /// Reads and decodes a single key by name. Uses cached key metadata, so a
    /// repeat read costs a single IOKit call (the value) instead of two.
    func read(_ key: String) throws -> SMCValue {
        let meta = try info(for: key)

        var data = SMCParamStruct()
        data.key = fourCharCode(key)
        data.keyInfoDataSize = meta.size
        data.data8 = SMC_CMD_READ_BYTES
        let dataOut = try call(&data)

        return SMCValue(key: key, type: meta.type, size: meta.size, bytes: dataOut.bytes)
    }

    /// Enumerates every key the SMC exposes. Cached after the first call.
    func allKeys() throws -> [String] {
        if let keyListCache { return keyListCache }
        let count = try keyCount()
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for i in 0..<count {
            if let k = try? key(at: i) { keys.append(k) }
        }
        keyListCache = keys
        return keys
    }

    /// The subset of keys that are temperature sensors: a `T…` key whose type
    /// is one of the temperature encodings. Fixed per machine, so it is
    /// computed once; repeat captures then read only these keys' live values.
    func temperatureKeys() throws -> [String] {
        if let tempKeyCache { return tempKeyCache }
        var keys: [String] = []
        for k in try allKeys() where k.hasPrefix("T") {
            if let meta = try? info(for: k), meta.type == "flt " || meta.type == "sp78" {
                keys.append(k)
            }
        }
        tempKeyCache = keys
        return keys
    }

    /// Number of fans (`FNum`), clamped and cached. Bounds a corrupt count the
    /// same way `keyCount()` does. Caches only on a successful read+decode so a
    /// transient failure doesn't permanently pin the count to 0.
    func fanCount() -> Int {
        if let fanCountCache { return fanCountCache }
        guard let raw = (try? read("FNum"))?.double else { return 0 }
        let n = clampedCount(raw, upperBound: 64)
        fanCountCache = n
        return n
    }

    /// Static min/max RPM limits for fan `i` (hardware-fixed; cached). Caches
    /// only when both limits decode, so a failed first attempt can be retried
    /// instead of masking the metadata for the connection's lifetime.
    func fanLimits(_ i: Int) -> (min: Double, max: Double) {
        if let cached = fanLimitsCache[i] { return cached }
        guard let mn = (try? read("F\(i)Mn"))?.double,
              let mx = (try? read("F\(i)Mx"))?.double else { return (0, 0) }
        let limits = (min: mn, max: mx)
        fanLimitsCache[i] = limits
        return limits
    }
}

// MARK: - FourCharCode helpers

func fourCharCode(_ s: String) -> UInt32 {
    let chars = Array(s.utf8)
    var result: UInt32 = 0
    for i in 0..<4 {
        let byte = i < chars.count ? chars[i] : UInt8(ascii: " ")
        result = result << 8 | UInt32(byte)
    }
    return result
}

func fourCharString(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? ""
}
