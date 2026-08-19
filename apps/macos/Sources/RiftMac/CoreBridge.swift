import CRift
import Foundation

struct CoreSnapshot: Decodable {
    let root: String
    let branch: String
    let changes: [CoreChange]
    let recentCommits: [CoreCommit]
}

struct CoreChange: Decodable {
    let indexStatus: String
    let worktreeStatus: String
    let path: String
}

struct CoreCommit: Decodable {
    let id: String
    let author: String
    let authoredAt: String
    let subject: String
}

struct CoreOperationState: Decodable {
    let operation: String?
    let conflicts: [String]
}

struct CoreGraphCommit: Decodable {
    let id: String
    let parents: [String]
    let references: [String]
    let author: String
    let authoredAt: String
    let subject: String
}

struct CoreDiffHunk: Decodable, Identifiable {
    let id: Int
    let header: String
    let patch: String
}

struct CoreRebaseStep: Codable, Identifiable {
    var action: String
    let commit: String
    let subject: String
    var id: String { commit }
}

struct CoreBlameLine: Decodable, Identifiable {
    let lineNumber: Int
    let commit: String
    let author: String
    let authoredAt: Int64
    let content: String
    var id: Int { lineNumber }
}

struct CoreHistoryEntry: Decodable, Identifiable {
    let id: String
    let author: String
    let authoredAt: String
    let subject: String
}

struct CoreWorktree: Decodable, Identifiable {
    let path: String
    let commit: String
    let branch: String?
    let isBare: Bool
    var id: String { path }
}

struct CoreSubmodule: Decodable, Identifiable {
    let path: String
    let commit: String
    let state: Character
    var id: String { path }
}

private struct CoreEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let value: Value?
    let error: String?
}

private struct ExecuteEnvelope: Decodable {
    let ok: Bool
    let error: String?
}

enum CoreBridge {
    static func inspect(_ path: String) throws -> CoreSnapshot {
        let pointer = path.withCString(rift_inspect_json)
        return try decode(pointer, as: CoreSnapshot.self)
    }

    static func operationState(_ path: String) throws -> CoreOperationState {
        let pointer = path.withCString(rift_operation_state_json)
        return try decode(pointer, as: CoreOperationState.self)
    }

    static func graph(_ path: String, limit: Int = 500) throws -> [CoreGraphCommit] {
        let pointer = path.withCString { rift_commit_graph_json($0, limit) }
        return try decode(pointer, as: [CoreGraphCommit].self)
    }

    static func hunks(_ path: String, file: String, staged: Bool) throws -> [CoreDiffHunk] {
        let pointer = path.withCString { pathPointer in
            file.withCString { filePointer in
                rift_file_hunks_json(pathPointer, filePointer, staged)
            }
        }
        return try decode(pointer, as: [CoreDiffHunk].self)
    }

    static func rebasePlan(_ path: String, upstream: String) throws -> [CoreRebaseStep] {
        let pointer = path.withCString { pathPointer in
            upstream.withCString { upstreamPointer in
                rift_interactive_rebase_plan_json(pathPointer, upstreamPointer)
            }
        }
        return try decode(pointer, as: [CoreRebaseStep].self)
    }

    static func blame(_ path: String, file: String) throws -> [CoreBlameLine] {
        let pointer = path.withCString { pathPointer in
            file.withCString { filePointer in rift_blame_json(pathPointer, filePointer) }
        }
        return try decode(pointer, as: [CoreBlameLine].self)
    }

    static func fileHistory(_ path: String, file: String) throws -> [CoreHistoryEntry] {
        let pointer = path.withCString { pathPointer in
            file.withCString { filePointer in rift_file_history_json(pathPointer, filePointer) }
        }
        return try decode(pointer, as: [CoreHistoryEntry].self)
    }

    static func worktrees(_ path: String) throws -> [CoreWorktree] {
        try decode(path.withCString(rift_worktrees_json), as: [CoreWorktree].self)
    }

    static func submodules(_ path: String) throws -> [CoreSubmodule] {
        try decode(path.withCString(rift_submodules_json), as: [CoreSubmodule].self)
    }

    static func execute(_ request: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CoreError.message("Could not encode native request")
        }
        let pointer = json.withCString(rift_execute_json)
        let responseData = try consume(pointer)
        let response = try JSONDecoder().decode(ExecuteEnvelope.self, from: responseData)
        if !response.ok { throw CoreError.message(response.error ?? "Git operation failed") }
    }

    private static func decode<Value: Decodable>(
        _ pointer: UnsafeMutablePointer<CChar>?,
        as type: Value.Type
    ) throws -> Value {
        let data = try consume(pointer)
        let response = try JSONDecoder().decode(CoreEnvelope<Value>.self, from: data)
        guard response.ok, let value = response.value else {
            throw CoreError.message(response.error ?? "Native core failed")
        }
        return value
    }

    private static func consume(_ pointer: UnsafeMutablePointer<CChar>?) throws -> Data {
        guard let pointer else { throw CoreError.message("Native core returned no response") }
        defer { rift_string_free(pointer) }
        return Data(String(cString: pointer).utf8)
    }
}

enum CoreError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}
