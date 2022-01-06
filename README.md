# AppUpdater

[![.github/workflows/ci.yml](https://github.com/niteoweb/AppUpdater/actions/workflows/ci.yml/badge.svg)](https://github.com/niteoweb/AppUpdater/actions/workflows/ci.yml)

A simple app-updater for macOS, checks your GitHub releases for a binary asset
once a day and silently updates your app. Forked from mxcl/AppUpdater.

Main changes:

- Removal of Promise based updater
- Public methods for getting info about latest version (What's new, etc..)
- Configurable update URL, interval of updates
- Runtime guard to prevent multiple instances

Used by:
- https://github.com/teamniteo/work-hours-mac


## Caveats

* We make no allowances for ensuring your app is not being actively used by the user
    at the time of update.
* Assets must be named: `AppName.zip`.
* Will not work if App is installed as a root user.

## Features

* Full semantic versioning support: we understand alpha/beta etc.
* We check the code-sign identity of the download matches the app that is running before doing the update.
* Restarts the app after update.
* Supports [.zip, .tar, .tar.xz].


## Usage

```swift
package.dependencies.append(.package(url: "https://github.com/niteoweb/AppUpdater.git", from: "2.0.0"))
```

Then:

```swift
import AppUpdater

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    static let updater = GithubAppUpdater(
        updateURL: "https://api.github.com/repos/teamniteo/work-hours-mac/releases",
        allowPrereleases: false,
        autoGuard: true,
        interval: 60 * 60
    )
    
    ...
    // force update if one present
    updater.update()
    
    // Custom runner
    @objc func checkForRelease() {
        let currentVersion = Bundle.main.version
        if let release = try? updater!.getLatestRelease() {
            #if !SETAPP_ENABLED
                if currentVersion < release.version {
                    if let zipURL = release.assets.filter({ $0.browser_download_url.path.hasSuffix(".zip") }).first {
                        let done = updater!.downloadAndUpdate(withAsset: zipURL)
                        // Failed to update
                        if !done {
                            Defaults[.updateNag] = true
                        }
                    }
                }
            #endif
        }
    }
}
```

## Alternatives

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Mac)
