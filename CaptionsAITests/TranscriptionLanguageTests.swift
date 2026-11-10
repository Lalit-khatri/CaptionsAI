@testable import CaptionsAI
import XCTest

final class TranscriptionLanguageTests: XCTestCase {
    // MARK: - The list

    func testEnglishComesFirstAndTheRestAreAlphabetical() {
        let all = TranscriptionLanguage.all
        XCTAssertEqual(all.first, .english)
        let rest = all.dropFirst().map(\.name)
        XCTAssertEqual(rest, rest.sorted())
    }

    func testEveryWhisperLanguageIsListedOnce() {
        // 99 in WhisperKit's table once its aliases are folded together,
        // less Cantonese, which only large-v3 knows; plus its English.
        let codes = TranscriptionLanguage.all.map(\.code)
        XCTAssertEqual(codes.count, 99)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertFalse(codes.contains("yue"))
    }

    func testTheRegionalLanguagesUsersAskedForAreThere() {
        XCTAssertEqual(TranscriptionLanguage.with(code: "kn")?.name, "Kannada")
        XCTAssertEqual(TranscriptionLanguage.with(code: "hi")?.name, "Hindi")
        XCTAssertEqual(TranscriptionLanguage.with(code: "ta")?.name, "Tamil")
        XCTAssertEqual(TranscriptionLanguage.with(code: "te")?.name, "Telugu")
        XCTAssertEqual(TranscriptionLanguage.with(code: "mr")?.name, "Marathi")
    }

    func testAnUnknownCodeIsNotALanguage() {
        XCTAssertNil(TranscriptionLanguage.with(code: "xx"))
    }

    // MARK: - Routing

    func testEnglishStaysOnApplesRecogniser() {
        XCTAssertEqual(TranscriptionLanguage.english.engine, .apple)
    }

    func testEveryOtherLanguageGoesToWhisper() {
        let notWhisper = TranscriptionLanguage.all.dropFirst().filter { $0.engine != .whisper }.map(\.code)
        XCTAssertEqual(notWhisper, [])
    }

    // MARK: - Native names

    func testKannadaKnowsItsOwnName() {
        XCTAssertEqual(TranscriptionLanguage.with(code: "kn")?.nativeName, "ಕನ್ನಡ")
    }

    func testANativeNameThatOnlyRepeatsTheEnglishOneIsDropped() {
        XCTAssertNil(TranscriptionLanguage.english.nativeName)
    }

    // MARK: - Search

    func testSearchMatchesTheStartOfTheEnglishName() {
        XCTAssertEqual(TranscriptionLanguage.matching("kan").map(\.code), ["kn"])
    }

    func testSearchIgnoresCase() {
        XCTAssertEqual(TranscriptionLanguage.matching("HINDI").map(\.code), ["hi"])
    }

    func testSearchMatchesTheNativeName() {
        XCTAssertEqual(TranscriptionLanguage.matching("ಕನ್ನ").map(\.code), ["kn"])
    }

    func testSearchMatchesAWordInsideTheName() {
        XCTAssertEqual(TranscriptionLanguage.matching("creole").map(\.code), ["ht"])
        XCTAssertEqual(TranscriptionLanguage.matching("burm").map(\.code), ["my"])
    }

    func testSearchDoesNotMatchTheMiddleOfAWord() {
        // "nada" is inside "Kannada"; a list that jumps around on every
        // letter typed is harder to use than one that matches word starts.
        XCTAssertEqual(TranscriptionLanguage.matching("nada"), [])
    }

    func testAnEmptyOrBlankSearchShowsEverything() {
        XCTAssertEqual(TranscriptionLanguage.matching(""), TranscriptionLanguage.all)
        XCTAssertEqual(TranscriptionLanguage.matching("   "), TranscriptionLanguage.all)
    }

    // MARK: - Preference

    private var defaults: UserDefaults!
    private let suiteName = "TranscriptionLanguageTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testThePreferenceStartsAsEnglish() {
        XCTAssertEqual(LanguagePreference(defaults: defaults).language, .english)
    }

    func testAChosenLanguageIsRemembered() {
        LanguagePreference(defaults: defaults).language = TranscriptionLanguage.with(code: "kn")!
        XCTAssertEqual(LanguagePreference(defaults: defaults).language.code, "kn")
    }

    func testAStoredCodeThisBuildDoesNotKnowReadsAsEnglish() {
        defaults.set("xx", forKey: LanguagePreference.key)
        XCTAssertEqual(LanguagePreference(defaults: defaults).language, .english)
    }
}
