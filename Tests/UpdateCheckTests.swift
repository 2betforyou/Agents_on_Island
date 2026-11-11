import Foundation
import XCTest
@testable import NotchAgent

final class UpdateCheckTests: XCTestCase {
    func testNumericVersionComparisonAndReleaseLink() throws {
        let result = try UpdateCheck.compare(release("v0.1.10"), installedVersion: "0.1.9")
        XCTAssertEqual(result, .available(version: "0.1.10",
                                         url: UpdateCheck.releases.appendingPathComponent("tag/v0.1.10")))
        XCTAssertEqual(try UpdateCheck.compare(release("v0.1.5"), installedVersion: "0.1.5"), .upToDate)
        XCTAssertEqual(try UpdateCheck.compare(release("v0.1.4"), installedVersion: "0.1.5"),
                       .aheadOfRelease(version: "0.1.4"))
    }

    func testRejectsNonReleaseAndMalformedTags() {
        XCTAssertThrowsError(try UpdateCheck.compare(release("v0.1.6", prerelease: true), installedVersion: "0.1.5"))
        XCTAssertThrowsError(try UpdateCheck.compare(release("v0.1.6", draft: true), installedVersion: "0.1.5"))
        XCTAssertThrowsError(try UpdateCheck.compare(release("v0..6"), installedVersion: "0.1.5"))
    }

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease)}"#.utf8)
    }
}
