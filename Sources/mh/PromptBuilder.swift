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

    static func analysis(_ deep: DeepSnapshot) throws -> AnalysisPrompt {
        let json = try encodeSnapshotJson(deep)
        let prompt = """
        You are analyzing a Mac diagnostic deep-dive. The deep snapshot below contains \
        both the original shallow signals from all four domains AND the deep probe data \
        for the dominant domain: \(deep.domain.rawValue.uppercased()).

        DEEP_SNAPSHOT:
        \(json)

        Write a multi-section markdown report explaining the root cause and prioritized \
        recommendations. Then propose 0-5 fix actions from the FixAction allowlist:

          - flush_dns                  (params: {})
          - restart_wifi               (params: {"interface": "<en0|en1|...>"})
          - quit_app                   (params: {"bundle_id": "<reverse-DNS bundle ID>"})
          - kill_pid                   (params: {"pid": <integer>})
          - clear_xcode_derived_data   (params: {})
          - clear_npm_cache            (params: {})
          - docker_stop_all            (params: {})

        Each fix MUST set `params_json` to a JSON-encoded string of the params object, \
        even when empty ("{}"). Set `dangerous: true` for any irreversible or data-losing \
        action (kill_pid of unsaved-data apps, clear_xcode_derived_data, docker_stop_all). \
        Respond ONLY with JSON matching the supplied schema.
        """
        guard let url = Bundle.module.url(forResource: "analysis_schema", withExtension: "json") else {
            throw BuilderError.missingResource("analysis_schema.json")
        }
        return AnalysisPrompt(prompt: prompt, schemaFile: url)
    }

    private static func encodeSnapshotJson<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
