import Foundation

enum Domain: String, Codable, CaseIterable, Sendable {
    case wifi
    case cpu
    case disk
    case battery
}
