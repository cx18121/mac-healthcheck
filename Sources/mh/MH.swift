import ArgumentParser

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis"
    )

    func run() async throws {
        print("mh v0.1 — not yet implemented")
    }
}
