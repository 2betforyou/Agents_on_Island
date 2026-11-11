import SwiftUI

enum UpdateCheck {
    static let releases = URL(string: "https://github.com/2betforyou/Agents_on_Island/releases")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/2betforyou/Agents_on_Island/releases/latest")!

    enum Result: Equatable {
        case available(version: String, url: URL)
        case upToDate
        case aheadOfRelease(version: String)
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    enum Failure: Error {
        case invalidResponse
    }

    static func fetch(installedVersion: String) async throws -> Result {
        var request = URLRequest(url: latestRelease, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.invalidResponse }
        return try compare(data, installedVersion: installedVersion)
    }

    static func compare(_ data: Data, installedVersion: String) throws -> Result {
        let release = try JSONDecoder().decode(Release.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard !release.draft, !release.prerelease,
              let latest = components(version), let installed = components(installedVersion) else {
            throw Failure.invalidResponse
        }
        if installed == latest { return .upToDate }
        if latest.lexicographicallyPrecedes(installed) { return .aheadOfRelease(version: version) }
        return .available(version: version, url: releases.appendingPathComponent("tag").appendingPathComponent(release.tag_name))
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(part)
        }
        guard numbers.count == parts.count else { return nil }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}

struct UpdateCheckSection: View {
    let installedVersion: String
    @State private var requestID: UUID?
    @State private var checking = false
    @State private var result: UpdateCheck.Result?
    @State private var failed = false

    var body: some View {
        Section(L("업데이트", "Updates")) {
            LabeledContent(L("설치된 버전", "Installed version"), value: installedVersion)
            HStack {
                Button(L("업데이트 확인", "Check for Updates")) {
                    checking = true
                    failed = false
                    result = nil
                    requestID = UUID()
                }
                .disabled(checking)
                if checking {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(L("확인 중", "Checking"))
                }
            }
            if let result {
                switch result {
                case .available(let version, let url):
                    Text(L("새 버전 \(version)이 있습니다.", "Version \(version) is available."))
                    Link(L("릴리즈 열기", "Open Release"), destination: url)
                case .upToDate:
                    Text(L("최신 버전을 사용 중입니다.", "You're up to date."))
                case .aheadOfRelease(let version):
                    Text(L("최신 공개 버전은 \(version)입니다.", "The latest public release is \(version)."))
                }
            }
            if failed {
                Text(L("업데이트를 확인하지 못했습니다. 잠시 후 다시 시도하세요.", "Couldn't check for updates. Try again in a moment."))
                    .foregroundStyle(.secondary)
                Link(L("GitHub 릴리즈 보기", "View GitHub Releases"), destination: UpdateCheck.releases)
            }
        }
        .task(id: requestID) {
            guard requestID != nil else { return }
            do {
                let latest = try await UpdateCheck.fetch(installedVersion: installedVersion)
                if !Task.isCancelled { result = latest }
            } catch {
                if !Task.isCancelled { failed = true }
            }
            if !Task.isCancelled { checking = false }
        }
    }
}
