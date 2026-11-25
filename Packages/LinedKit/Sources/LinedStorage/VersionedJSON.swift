import Foundation

/// A JSON file whose top level carries a `formatVersion`, so older files can be migrated and newer ones refused.
protocol VersionedFile: Codable {
    static var currentFormatVersion: Int { get }
    var formatVersion: Int { get }
}

enum VersionedJSON {
    static func read<File: VersionedFile>(_ type: File.Type, from url: URL) throws -> File {
        let data = try Data(contentsOf: url)
        guard let probe = try? decoder.decode(FormatVersionProbe.self, from: data) else {
            throw StorageError.corruptFile(url)
        }
        guard probe.formatVersion <= File.currentFormatVersion else {
            throw StorageError.unsupportedFormatVersion(found: probe.formatVersion, supported: File.currentFormatVersion)
        }
        do {
            return try decoder.decode(File.self, from: data)
        } catch {
            throw StorageError.corruptFile(url)
        }
    }

    static func write(_ file: some VersionedFile, to url: URL) throws {
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    private struct FormatVersionProbe: Decodable {
        let formatVersion: Int
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(timestampStyle))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = try? timestampStyle.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp.")
            }
            return date
        }
        return decoder
    }
}

extension FileManager {
    func itemExists(at url: URL) -> Bool {
        fileExists(atPath: url.path(percentEncoded: false))
    }
}
