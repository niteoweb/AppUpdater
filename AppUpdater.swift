import var AppKit.NSApp
import Cocoa
import Foundation
import os.log
import Path
import Version

public enum UpdaterError: Swift.Error {
    case bundleExecutableURL
    case codeSigningIdentity
    case invalidDownloadedBundle
    case badInput
}

public class GithubAppUpdater {
    let activity: NSBackgroundActivityScheduler?
    let url: URL
    let allowPrereleases: Bool

    public init(
        updateURL: String,
        allowPrereleases: Bool = false,
        autoGuard: Bool = true,
        interval: TimeInterval = 24 * 60 * 60
    ) {
        url = URL(string: updateURL)!
        self.allowPrereleases = allowPrereleases

        // Prevent multiple running apps after the update
        // Terminate oldest process
        let processes = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if processes.count > 1, autoGuard {
            processes.first?.forceTerminate()
        }
        if interval > 0 {
            activity = NSBackgroundActivityScheduler(identifier: "\(String(describing: Bundle.main.bundleIdentifier)).Updater")
            activity?.repeats = true
            activity?.interval = interval
            activity?.schedule { completion in
                _ = self.checkAndUpdate()
                completion(.finished)
            }
        } else {
            activity = nil
        }
    }

    public func checkAndUpdate() -> Bool {
        let currentVersion = Bundle.main.version
        if let release = try? getLatestRelease(allowPrereleases: allowPrereleases) {
            if currentVersion < release.version {
                if let zipURL = release.assets.filter({ $0.browserDownloadURL.path.hasSuffix(".zip") }).first {
                    return downloadAndUpdate(withAsset: zipURL)
                }
            }
        }
        return false
    }

    deinit {
        activity?.invalidate()
    }

    public func getLatestRelease(allowPrereleases prerelease: Bool) throws -> Release? {
        guard Bundle.main.executableURL != nil else {
            throw UpdaterError.bundleExecutableURL
        }

        let data = try Data(contentsOf: url)
        let releases = try JSONDecoder().decode([Release].self, from: data)
        let release = try releases.findViableUpdate(prerelease: prerelease)
        return release
    }

    public func downloadAndUpdate(withAsset asset: Release.Asset) -> Bool {
        #if DEBUG
            os_log("In debug target updates are disabled! Asset: %s", asset.browserDownloadURL.debugDescription)
            return false
        #else
            let lock = DispatchSemaphore(value: 0)
            var state = false
            let tempDirectory = try! FileManager.default.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: Bundle.main.bundleURL,
                create: true
            )

            URLSession.shared.downloadTask(with: asset.browserDownloadURL) { tempLocalUrl, response, error in
                if error != nil {
                    os_log("Error took place while downloading a file: \(error!.localizedDescription)")
                    lock.signal()
                    return
                }

                if let tempLocalUrl = tempLocalUrl {
                    // Success
                    if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                        if statusCode != 200 {
                            os_log("Failed to download \(asset.browserDownloadURL). Status code: \(statusCode)")
                            lock.signal()
                            return
                        }

                        os_log("Successfully downloaded \(asset.browserDownloadURL). Status code: \(statusCode)")
                        let downloadPath = tempDirectory.appendingPathComponent("download")
                        do {
                            try FileManager.default.copyItem(at: tempLocalUrl, to: downloadPath)
                        } catch let writeError {
                            os_log("Error moving a file \(tempLocalUrl) to \(downloadPath): \(writeError.localizedDescription)")
                            lock.signal()
                        }

                        os_log("Doing update from \(tempLocalUrl)")
                        do {
                            try self.update(withApp: downloadPath, withAsset: asset)
                            state = true
                            lock.signal()
                        } catch let writeError {
                            os_log("Error updating with file \(downloadPath) : \(writeError.localizedDescription)")
                            lock.signal()
                        }
                    } else {
                        os_log("Could not parse response of \(asset.browserDownloadURL)")
                        lock.signal()
                    }
                } else {
                    os_log("Error updating from \(asset.browserDownloadURL), missing local file")
                    lock.signal()
                }
            }.resume()
            lock.wait()
            try? FileManager.default.removeItem(at: tempDirectory)
            return state
        #endif
    }

    private func validate(_ b1: Bundle, _ b2: Bundle) -> Bool {
        b1.codeSigningIdentity == b2.codeSigningIdentity
    }

    private func update(withApp destination: URL, withAsset asset: Release.Asset) throws {
        let bundlePath = unzip(destination, contentType: asset.contentType)
        let downloadedAppBundle = Bundle(url: bundlePath)!
        let installedAppBundle = Bundle.main
        guard let exe = downloadedAppBundle.executable, exe.exists else {
            throw UpdaterError.invalidDownloadedBundle
        }
        let finalExecutable = installedAppBundle.path / exe.relative(to: downloadedAppBundle.path)
        if validate(downloadedAppBundle, installedAppBundle) {
            do {
                try installedAppBundle.path.delete()
                os_log("Delete installedAppBundle: \(installedAppBundle)")
                try downloadedAppBundle.path.move(to: installedAppBundle.path)
                os_log("Move new app to installedAppBundle: \(installedAppBundle)")
                // runOSA(appleScript: "activate application \"Pareto Security\"")
                let proc = Process()
                if #available(OSX 10.13, *) {
                    proc.executableURL = finalExecutable.url
                } else {
                    proc.launchPath = finalExecutable.string
                }
                proc.launch()
                DispatchQueue.main.async {
                    NSApp.terminate(self)
                }

            } catch {
                os_log("Failed update: \(error.localizedDescription)")
                throw UpdaterError.invalidDownloadedBundle
            }
        } else {
            os_log("Failed codeSigningIdentity")
            throw UpdaterError.codeSigningIdentity
        }
    }
}

private func unzip(_ url: URL, contentType: Release.Asset.ContentType) -> URL {
    let proc = Process()
    if #available(OSX 10.13, *) {
        proc.currentDirectoryURL = url.deletingLastPathComponent()
    } else {
        proc.currentDirectoryPath = url.deletingLastPathComponent().path
    }

    switch contentType {
    case .tar:
        proc.launchPath = "/usr/bin/tar"
        proc.arguments = ["xf", url.path]
    case .zip:
        proc.launchPath = "/usr/bin/unzip"
        proc.arguments = [url.path]
    case .unknown:
        proc.launchPath = "/usr/bin/unzip"
        proc.arguments = [url.path]
    }
    func findApp() throws -> URL? {
        let files = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey], options: .skipsSubdirectoryDescendants)
        for url in files {
            guard url.pathExtension == "app" else { continue }
            guard let foo = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, foo else { continue }
            return url
        }
        return nil
    }
    proc.launch()
    proc.waitUntilExit()
    return try! findApp()!
}
