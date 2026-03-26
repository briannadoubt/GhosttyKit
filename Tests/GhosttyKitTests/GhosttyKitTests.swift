import XCTest
import GhosttyKit

final class GhosttyKitTests: XCTestCase {
    func testGhosttyInfoExposesAVersion() {
        let info = ghostty_info()

        XCTAssertNotNil(info.version)
        XCTAssertGreaterThan(info.version_len, 0)

        guard let versionPointer = info.version else {
            return XCTFail("ghostty_info() returned a nil version pointer")
        }

        let versionBytes = UnsafeBufferPointer(start: versionPointer, count: Int(info.version_len))
        let version = String(decoding: versionBytes.map(UInt8.init(bitPattern:)), as: UTF8.self)

        XCTAssertFalse(version.isEmpty)
    }
}
