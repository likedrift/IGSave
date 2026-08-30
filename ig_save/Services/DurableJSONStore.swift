//
//  DurableJSONStore.swift
//  IGSave
//

import Foundation

enum DurableJSONStore {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) -> Value? {
        if let data = try? Data(contentsOf: url),
           let value = try? decoder.decode(type, from: data) {
            let backupURL = backupURL(for: url)
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try? data.write(to: backupURL, options: [.atomic, .completeFileProtection])
            }
            return value
        }

        let backupURL = backupURL(for: url)
        guard let backupData = try? Data(contentsOf: backupURL),
              let value = try? decoder.decode(type, from: backupData) else {
            return nil
        }

        try? prepareDirectory(for: url)
        try? backupData.write(to: url, options: [.atomic, .completeFileProtection])
        return value
    }

    @discardableResult
    static func persist<Value: Encodable>(
        _ value: Value,
        to url: URL,
        encoder: JSONEncoder = JSONEncoder()
    ) -> Bool {
        guard let data = try? encoder.encode(value) else { return false }

        do {
            try prepareDirectory(for: url)

            if let existingData = try? Data(contentsOf: url), !existingData.isEmpty {
                try existingData.write(
                    to: backupURL(for: url),
                    options: [.atomic, .completeFileProtection]
                )
            }

            try data.write(to: url, options: [.atomic, .completeFileProtection])
            let backupURL = backupURL(for: url)
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                try? data.write(to: backupURL, options: [.atomic, .completeFileProtection])
            }
            return true
        } catch {
            return false
        }
    }

    static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("backup")
    }

    private static func prepareDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
