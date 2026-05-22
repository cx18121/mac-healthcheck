import Foundation

struct TriagePrompt {
    let prompt: String
    let schemaFile: URL
}

struct AnalysisPrompt {
    let prompt: String
    let schemaFile: URL
}

enum PromptBuilder {

    enum BuilderError: Error {
        case missingResource(String)
    }

    static func triage(_ snapshot: ShallowSnapshot) throws -> TriagePrompt {
        let snapshotJson = try encodeSnapshotJson(snapshot)
        let prompt = """
        You are diagnosing a Mac. Below are shallow health signals across four domains \
        (CPU, WiFi, disk, battery). Probes that could not run are marked with a \
        non-"ok" status field.

        SHALLOW_SNAPSHOT:
        \(snapshotJson)

        Choose the SINGLE most concerning domain (or "none" if everything looks normal). \
        Respond ONLY with JSON matching the supplied schema. The reasoning field should \
        explain in <=300 chars why this domain is the most concerning.
        """

        guard let url = Bundle.module.url(forResource: "triage_schema", withExtension: "json") else {
            throw BuilderError.missingResource("triage_schema.json")
        }
        return TriagePrompt(prompt: prompt, schemaFile: url)
    }

    // (analysis() added in Task 14)

    private static func encodeSnapshotJson<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
