import Foundation

enum SaveJobStore {
    private static let maxCount = 50

    static func load() -> [SaveJob] {
        guard
            let data = try? Data(contentsOf: storageURL()),
            var jobs = try? JSONDecoder().decode([SaveJob].self, from: data)
        else {
            return []
        }

        for index in jobs.indices where jobs[index].status.isRunning || jobs[index].status == .idle {
            jobs[index].status = .queued
        }

        return Array(jobs.prefix(maxCount))
    }

    static func persist(_ jobs: [SaveJob]) {
        guard let data = try? JSONEncoder().encode(Array(jobs.prefix(maxCount))) else {
            return
        }

        let url = storageURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaveJobs", isDirectory: true)
            .appendingPathComponent("save-jobs-v1.json")
    }
}
