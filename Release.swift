//
//  File.swift
//  AppUpdater
//
//  Created by Janez Troha on 29/12/2021.
//

import Foundation
import Version

struct Release: Decodable {
    let tagName: String
    let prerelease: Bool
    let assets: [Asset]
    let body: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease, assets, body
    }

    var version: Version {
        if let ver = Version(tagName) {
            return ver
        }
        return Version(0, 0, 0)
    }

    struct Asset: Decodable {
        let name: String

        let size: Int
        let browserDownloadURL: URL
        let contentType: ContentType

        enum ContentType: Decodable {
            init(from decoder: Decoder) throws {
                switch try decoder.singleValueContainer().decode(String.self) {
                case "application/x-bzip2", "application/x-xz", "application/x-gzip":
                    self = .tar
                case "application/zip":
                    self = .zip
                default:
                    self = .unknown
                }
            }

            case zip
            case tar
            case unknown
        }

        enum CodingKeys: String, CodingKey {
            case name
            case contentType = "content_type"
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }
}

extension Array where Element == Release {
    func findViableUpdate(prerelease: Bool) throws -> Release? {
        let suitableReleases = !prerelease ? filter { $0.prerelease == false } : filter { $0.prerelease == true }
        guard let latestRelease = suitableReleases.sorted(by: {
            $0.version < $1.version
        }).filter({ $0.assets.count > 0 }).last else { return nil }
        return latestRelease
    }
}
