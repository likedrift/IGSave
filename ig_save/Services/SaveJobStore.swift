import Foundation

enum SaveJobStore {
    private static let maxCount = 50

    static func load() -> [SaveJob] {
        guard let jobs = DurableJSONStore.load([SaveJob].self, from: storageURL()) else {
            return []
        }

        let restoredJobs = restored(jobs)
        if restoredJobs != jobs {
            persist(restoredJobs)
        }
        return restoredJobs
    }

    static func restored(_ storedJobs: [SaveJob], now: Date = Date()) -> [SaveJob] {
        var jobs = storedJobs
        for index in jobs.indices where jobs[index].status.isRunning || jobs[index].status == .idle {
            jobs[index].status = .queued
            jobs[index].attemptID = nil
            jobs[index].updatedAt = now
        }

        jobs.removeAll { job in
            if case .saved = job.status { return true }
            return false
        }

        return Array(jobs.prefix(maxCount))
    }

    static func persist(_ jobs: [SaveJob]) {
        DurableJSONStore.persist(Array(jobs.prefix(maxCount)), to: storageURL())
    }

    private static func storageURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SaveJobs", isDirectory: true)
            .appendingPathComponent("save-jobs-v1.json")
    }
}
