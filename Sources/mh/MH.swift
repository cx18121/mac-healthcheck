import ArgumentParser

@main
struct MH: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mh",
        abstract: "macOS diagnostic CLI with LLM synthesis",
        subcommands: [Doctor.self]
    )

    func run() async throws {
        print("mh v0.1 — pipeline not yet wired; try `mh doctor`")
    }
}
