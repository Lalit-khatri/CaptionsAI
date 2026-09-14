import XCTest

@testable import CaptionsAI

/// The privacy manifest is the one App Store requirement that fails *before* a
/// human sees the build.
///
/// The app reads and writes `UserDefaults` in two places — the onboarding flag
/// in `AppState` and the daily export quota in `ExportViewModel` — and
/// `UserDefaults` is a Required Reason API. A build without a manifest
/// declaring it is rejected by App Store Connect during upload processing
/// (ITMS-91053), not during review. Nothing in the app misbehaves, no test
/// fails, and the simulator is perfectly happy; the omission surfaces on
/// submission day and not one minute earlier.
///
/// That invisibility is the whole reason this file exists. These tests run
/// against the real app bundle (the test target sets `TEST_HOST`, so
/// `Bundle.main` here is `CaptionsAI.app`), which means they check the thing
/// that actually ships rather than a file sitting in the repo. A manifest that
/// is present in source but missing from target membership is the most common
/// way this stays broken after someone believes they have fixed it, and that
/// mistake fails these tests exactly as loudly as having no manifest at all.
final class PrivacyManifestTests: XCTestCase {

    private func manifest(file: StaticString = #filePath, line: UInt = #line) throws
        -> [String: Any]
    {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            """
            PrivacyInfo.xcprivacy is not in the built app bundle. Either the file \
            does not exist, or it exists in the repo but is not a resource of the \
            CaptionsAI target.
            """,
            file: file, line: line
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(
            plist as? [String: Any],
            "PrivacyInfo.xcprivacy is not a plist dictionary.",
            file: file, line: line
        )
    }

    func testTheManifestShipsInsideTheAppBundle() throws {
        _ = try manifest()
    }

    /// `CA92.1` is "access info from same app, per documentation" — i.e. the app
    /// reading back its own settings. It is the correct reason here precisely
    /// because there is no App Group: `1C8F.1` would claim the defaults are
    /// shared with an app extension or another app in a group, and
    /// `CaptionsAI.entitlements` declares no group at all.
    func testUserDefaultsIsDeclaredWithTheAppOnlyStorageReason() throws {
        let apis = try XCTUnwrap(
            manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "The manifest declares no accessed-API types."
        )
        let entry = try XCTUnwrap(
            apis.first {
                $0["NSPrivacyAccessedAPIType"] as? String
                    == "NSPrivacyAccessedAPICategoryUserDefaults"
            },
            """
            UserDefaults is not declared. AppState and ExportViewModel both use \
            UserDefaults.standard, so this category is required.
            """
        )
        XCTAssertEqual(
            entry["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"],
            "UserDefaults is declared with the wrong reason code."
        )
    }

    /// The app is offline and sends nothing anywhere. If that ever stops being
    /// true, this test is the tripwire: whoever adds analytics, a crash
    /// reporter or a network call has to come here and say so out loud.
    func testTheManifestClaimsNoTrackingAndNoCollection() throws {
        let contents = try manifest()
        XCTAssertEqual(
            contents["NSPrivacyTracking"] as? Bool, false,
            "The app does not track users."
        )
        XCTAssertEqual(
            (contents["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true,
            "The app contacts no tracking domains."
        )
        XCTAssertEqual(
            (contents["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.isEmpty, true,
            "The app collects no data, which is what the nutrition label claims."
        )
    }

    /// Guards the mistake three separate designs for the in-app feedback button
    /// were about to make. `sysctlbyname` is the gateway symbol for the system
    /// boot-time category, and Apple's scanner reads *symbols in the binary*,
    /// not the key string passed to them — so calling it for `hw.machine` to
    /// label a bug report trips the same wire as reading uptime. If the device
    /// model is ever genuinely wanted, declare `NSPrivacyAccessedAPICategorySystemBootTime`
    /// with reason `3D61.1` rather than deleting this test.
    func testNoBootTimeCategoryIsDeclaredBecauseNothingCallsSysctl() throws {
        let apis = (try manifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
        let declared = apis.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        XCTAssertFalse(
            declared.contains("NSPrivacyAccessedAPICategorySystemBootTime"),
            """
            The boot-time category is declared, which means something now calls \
            sysctlbyname. If that is deliberate, update this test; if it crept \
            in with a diagnostics payload, remove the call instead.
            """
        )
    }
}
