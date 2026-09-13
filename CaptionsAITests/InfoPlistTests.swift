@testable import CaptionsAI
import XCTest

/// Assertions about the shipped `Info.plist`.
///
/// These read the *built* bundle rather than the source file, so they fail if
/// the value is right in `Info.plist` but overridden by a build setting — the
/// failure mode a source-file check would miss entirely.
final class InfoPlistTests: XCTestCase {
    /// `Project` is defined in the app target, so this resolves to the app
    /// bundle. Anchoring on a class declared *here* would resolve to the test
    /// bundle and assert against the wrong plist.
    private let appBundle = Bundle(for: Project.self)

    func testRequiredDeviceCapabilitiesIsArm64() throws {
        let capabilities = try XCTUnwrap(
            appBundle.object(forInfoDictionaryKey: "UIRequiredDeviceCapabilities") as? [String],
            "UIRequiredDeviceCapabilities missing from the built app"
        )

        // armv7 is 32-bit. No device that can run iOS 17 has it, so declaring
        // it asks the App Store to filter the app down to an empty set of
        // devices. It is also flagged at submission.
        XCTAssertFalse(capabilities.contains("armv7"), "armv7 on an iOS 17 / arm64-only app")
        XCTAssertEqual(capabilities, ["arm64"])
    }

    func testDeploymentTargetIsAtLeastIOS17() throws {
        let minimum = try XCTUnwrap(
            appBundle.object(forInfoDictionaryKey: "MinimumOSVersion") as? String
        )
        let major = try XCTUnwrap(minimum.split(separator: ".").first.flatMap { Int($0) })
        XCTAssertGreaterThanOrEqual(major, 17, "the app uses SwiftData and @Observable")
    }
}
