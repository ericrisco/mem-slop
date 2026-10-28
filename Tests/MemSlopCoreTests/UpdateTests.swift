import Foundation
import Testing
@testable import MemSlopCore

@Suite struct SemanticVersionTests {
    @Test func comparesNumerically() throws {
        let v = { (text: String) throws -> SemanticVersion in try #require(SemanticVersion(text)) }
        #expect(try v("1.10.0") > v("1.9.3"))
        #expect(try v("v1.2.0") == v("1.2"))
        #expect(try v("2.0.0") > v("1.99.99"))
        #expect(try !(v("1.2.0") < v("1.2.0")))
        #expect(SemanticVersion("1.2.0-beta") == nil)
        #expect(SemanticVersion("dev") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
    }
}

@Suite struct ReleaseInfoTests {
    private func release(tag: String = "v1.3.1", draft: Bool = false, prerelease: Bool = false, assets: [String] = ["MemSlop.zip", "MemSlop.zip.sha256"]) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/ericrisco/mem-slop/releases/download/\#(tag)/\#($0)"}"# }
        return Data(#"{"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(prerelease),"html_url":"https://github.com/ericrisco/mem-slop/releases/tag/\#(tag)","body":"Fixed: things","assets":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    @Test func parsesALatestRelease() throws {
        let info = try #require(ReleaseInfo.parse(release()))
        #expect(info.version == SemanticVersion("1.3.1"))
        #expect(info.archiveURL.lastPathComponent == "MemSlop.zip")
        #expect(info.checksumURL.lastPathComponent == "MemSlop.zip.sha256")
        #expect(info.notes.contains("things"))
    }

    @Test func rejectsDraftsPrereleasesAndIncompleteReleases() {
        #expect(ReleaseInfo.parse(release(draft: true)) == nil)
        #expect(ReleaseInfo.parse(release(prerelease: true)) == nil)
        #expect(ReleaseInfo.parse(release(assets: ["MemSlop.zip"])) == nil)
        #expect(ReleaseInfo.parse(release(tag: "nightly")) == nil)
        #expect(ReleaseInfo.parse(Data("not json".utf8)) == nil)
    }

    @Test func parsesShasumLines() {
        let hash = String(repeating: "aB", count: 32)
        #expect(ReleaseInfo.parseChecksum("\(hash)  MemSlop.zip\n") == hash.lowercased())
        #expect(ReleaseInfo.parseChecksum("short  MemSlop.zip") == nil)
        #expect(ReleaseInfo.parseChecksum("") == nil)
    }
}
