import AppKit

// Bundle lookups are too slow for every event, so verdicts are cached per pid.
final class ExclusionCache {
    private let settings: Settings
    private var entries: [pid_t: (app: NSRunningApplication, excluded: Bool)] = [:]
    private var revision = -1

    init(settings: Settings) {
        self.settings = settings
    }

    func isExcluded(pid: pid_t) -> Bool {
        guard pid != 0, !settings.excludedApps.isEmpty else { return false }
        if revision != settings.excludedRevision {
            entries.removeAll()
            revision = settings.excludedRevision
        }
        // Background apps never post a termination notice, so a dead entry is detected here instead.
        if let entry = entries[pid], !entry.app.isTerminated { return entry.excluded }
        // Nothing is cached while the app is not resolvable yet, e.g. right after launch.
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        let excluded = settings.isExcluded(bundleID: app.bundleIdentifier)
        entries[pid] = (app, excluded)
        return excluded
    }
}
