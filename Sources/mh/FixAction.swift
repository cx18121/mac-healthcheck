import Foundation

enum FixAction: String, Codable, Sendable {
    case flushDns = "flush_dns"
    case restartWifi = "restart_wifi"
    case quitApp = "quit_app"
    case killPid = "kill_pid"
    case clearXcodeDerivedData = "clear_xcode_derived_data"
    case clearNpmCache = "clear_npm_cache"
    case dockerStopAll = "docker_stop_all"
}

struct ProposedFix: Codable, Sendable {
    let id: Int
    let action: FixAction
    let paramsJson: String       // raw JSON string from Codex
    let description: String
    let dangerous: Bool

    enum CodingKeys: String, CodingKey {
        case id, action, description, dangerous
        case paramsJson = "params_json"
    }
}

// Per-action param structs. Decoded from `paramsJson` by FixExecutor.
struct FlushDnsParams: Codable, Sendable {}
struct RestartWifiParams: Codable, Sendable { let interface: String }
struct QuitAppParams: Codable, Sendable { let bundle_id: String }
struct KillPidParams: Codable, Sendable { let pid: Int32 }
struct ClearXcodeDerivedDataParams: Codable, Sendable {}
struct ClearNpmCacheParams: Codable, Sendable {}
struct DockerStopAllParams: Codable, Sendable {}

/// Per-action dangerous fallback table (used if Codex forgets to flag).
extension FixAction {
    var dangerousByDefault: Bool {
        switch self {
        case .killPid, .clearXcodeDerivedData, .dockerStopAll: return true
        case .flushDns, .restartWifi, .quitApp, .clearNpmCache: return false
        }
    }
}
