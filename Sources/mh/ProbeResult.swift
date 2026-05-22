import Foundation

/// Outcome of running a single signal probe. Probes never throw — every
/// failure mode is a typed case so the caller can build a partial snapshot.
enum ProbeResult<T: Sendable>: Sendable {
    case value(T)
    case unavailable        // the probe binary is not installed (e.g. docker missing)
    case timedOut           // hit the per-probe timeout
    case failed(String)     // ran but produced unexpected output / non-zero exit

    var isSuccess: Bool {
        if case .value = self { return true }
        return false
    }
}
