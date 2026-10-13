import Foundation

// Headless check that exercises the app's real clients against the live servers and prints the
// exact error for anything that fails. Build/run with ./diagnose.sh.

// Reads the settings the app saved (current bundle ID first, then the pre-App Store one).
let config: AppConfig = {
    for domain in ["com.jakewatts.downarr", "local.downarr.Downarr"] {
        if let data = UserDefaults(suiteName: domain)?.data(forKey: "downarr.config.v1"),
           let saved = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return saved
        }
    }
    print("No saved Downarr settings found. Configure the servers in the app first.")
    exit(1)
}()

func report(_ label: String, _ work: @escaping () async throws -> String) async {
    let start = Date()
    do {
        let summary = try await work()
        print(String(format: "OK   %-28@ %5.2fs  %@", label as NSString,
                     Date().timeIntervalSince(start), summary as NSString))
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        print(String(format: "FAIL %-28@ %5.2fs", label as NSString, Date().timeIntervalSince(start)))
        print("     \(message.prefix(1200))")
    }
}

let sonarr = try? SonarrClient(endpoint: config.sonarr)
let radarr = try? RadarrClient(endpoint: config.radarr)
let nzbget = try? NZBGetClient(endpoint: config.nzbget)
let deluge = try? DelugeClient(endpoint: config.deluge)

await report("sonarr /series") {
    let list = try await sonarr!.series()
    return "\(list.count) series"
}
await report("sonarr /system/status") { try await sonarr!.status().version ?? "?" }
await report("sonarr /health") { "\(try await sonarr!.health().count) items" }
await report("sonarr /qualityprofile") { "\(try await sonarr!.qualityProfiles().count)" }
await report("sonarr /rootfolder") { "\(try await sonarr!.rootFolders().count)" }
await report("sonarr /diskspace") { "\(try await sonarr!.diskSpace().count)" }
await report("sonarr /queue") { "\(try await sonarr!.queue().records?.count ?? 0) records" }

await report("radarr /movie") {
    let list = try await radarr!.movies()
    return "\(list.count) movies"
}
await report("radarr /system/status") { try await radarr!.status().version ?? "?" }
await report("radarr /queue") { "\(try await radarr!.queue().records?.count ?? 0) records" }

await report("nzbget status") { "rate \(try await nzbget!.status().DownloadRate ?? 0)" }
await report("nzbget listgroups") { "\(try await nzbget!.groups().count) groups" }

await report("deluge login + update_ui") {
    guard try await deluge!.login() else { return "login refused" }
    let ui = try await deluge!.updateUI()
    return "\(ui.torrents?.count ?? 0) torrents"
}

let auth = try? await JellyfinClient.authenticate(endpoint: config.jellyfin,
                                                  deviceID: "downarr-diagnose")
if let token = auth?.AccessToken, let user = auth?.User {
    let jelly = try? JellyfinClient(endpoint: config.jellyfin, token: token,
                                    userID: user.Id, deviceID: "downarr-diagnose")
    await report("jellyfin /System/Info") { try await jelly!.systemInfo().Version ?? "?" }
    await report("jellyfin /Items/Counts") { "\(try await jelly!.counts().ItemCount ?? 0) items" }
    await report("jellyfin virtual folders") { "\(try await jelly!.virtualFolders().count) libraries" }
    await report("jellyfin /Items/Latest") { "\(try await jelly!.latest(parentID: nil, limit: 12).count) items" }
    await report("jellyfin scheduled tasks") { "\(try await jelly!.scheduledTasks().count) tasks" }
} else {
    print("FAIL jellyfin authentication")
}

// Now the part that matters: everything at once, exactly as AppState.bootstrap() does it.
print("\n--- concurrent bootstrap simulation ---")
async let a: Void = report("concurrent sonarr /series") { "\(try await sonarr!.series().count)" }
async let b: Void = report("concurrent radarr /movie") { "\(try await radarr!.movies().count)" }
async let c: Void = report("concurrent nzbget") { "\(try await nzbget!.groups().count)" }
async let d: Void = report("concurrent deluge") {
    _ = try await deluge!.login()
    return "\(try await deluge!.updateUI().torrents?.count ?? 0)"
}
_ = await (a, b, c, d)
