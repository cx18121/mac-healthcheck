import Foundation

// MARK: - Shallow per-domain structs

struct CPUShallow: Codable, Sendable {
    let loadAverage: [Double]      // 1, 5, 15 minute
    let topProcesses: [TopProcess] // up to 5
}

struct TopProcess: Codable, Sendable {
    let pid: Int32
    let cpuPercent: Double
    let memoryMB: Double
    let command: String
}

struct WifiShallow: Codable, Sendable {
    let ssid: String?
    let rssi: Int?         // dBm; nil if not associated
    let channel: Int?
    let linkRateMbps: Double?
    let interface: String  // e.g. "en0"
}

struct DiskShallow: Codable, Sendable {
    let mounts: [MountUsage]
}

struct MountUsage: Codable, Sendable {
    let mountPoint: String
    let percentFull: Int
    let availableGB: Double
}

struct BatteryShallow: Codable, Sendable {
    let percent: Int
    let onAC: Bool
    let charging: Bool
    let timeToEmptyMinutes: Int?
}

// MARK: - Composite snapshots

struct ShallowSnapshot: Codable, Sendable {
    let cpu: ProbeResultBox<CPUShallow>
    let wifi: ProbeResultBox<WifiShallow>
    let disk: ProbeResultBox<DiskShallow>
    let battery: ProbeResultBox<BatteryShallow>
    let timestamp: Date
}

// MARK: - Deep snapshot (domain-specific union)

struct DeepSnapshot: Codable, Sendable {
    let domain: Domain
    let shallow: ShallowSnapshot
    let deep: DeepData
    let timestamp: Date
}

enum DeepData: Codable, Sendable {
    case cpu(CPUDeep)
    case wifi(WifiDeep)
    case disk(DiskDeep)
    case battery(BatteryDeep)
}

struct CPUDeep: Codable, Sendable {
    let fullTopOutput: String       // raw top with more rows (truncated to 4KB)
    let thermalPressure: String     // pmset -g therm output
    let uptimeSeconds: Int
}

struct WifiDeep: Codable, Sendable {
    let systemProfilerOutput: String  // truncated SPAirPortDataType section
    let dnsTimingMs: Double?
    let gatewayPingMs: Double?
    let traceroute: String?           // first 5 hops, truncated
}

struct DiskDeep: Codable, Sendable {
    let topDirectories: [DiskUsage]   // du -sh on known cache paths
    let purgeableGB: Double?
}

struct DiskUsage: Codable, Sendable {
    let path: String
    let sizeGB: Double
}

struct BatteryDeep: Codable, Sendable {
    let pmsetGFull: String           // pmset -g
    let powerHistory: String         // pmset -g log | tail -50 (truncated)
    let cycleCount: Int?
}

// MARK: - JSON-friendly wrapper for ProbeResult

/// `ProbeResult<T>` cannot directly conform to `Codable` because it has an associated value
/// that varies. We wrap it for encoding into prompts.
enum ProbeResultBox<T: Codable & Sendable>: Codable, Sendable {
    case value(T)
    case unavailable
    case timedOut
    case failed(String)

    init(_ result: ProbeResult<T>) {
        switch result {
        case .value(let v): self = .value(v)
        case .unavailable: self = .unavailable
        case .timedOut: self = .timedOut
        case .failed(let msg): self = .failed(msg)
        }
    }

    private enum CodingKeys: String, CodingKey { case status, value, message }
    private enum Status: String, Codable { case ok, unavailable, timedOut, failed }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let v):
            try c.encode(Status.ok, forKey: .status)
            try c.encode(v, forKey: .value)
        case .unavailable:
            try c.encode(Status.unavailable, forKey: .status)
        case .timedOut:
            try c.encode(Status.timedOut, forKey: .status)
        case .failed(let msg):
            try c.encode(Status.failed, forKey: .status)
            try c.encode(msg, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status = try c.decode(Status.self, forKey: .status)
        switch status {
        case .ok: self = .value(try c.decode(T.self, forKey: .value))
        case .unavailable: self = .unavailable
        case .timedOut: self = .timedOut
        case .failed: self = .failed(try c.decode(String.self, forKey: .message))
        }
    }
}
