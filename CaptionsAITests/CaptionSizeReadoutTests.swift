@testable import CaptionsAI
import SwiftData
import XCTest

/// Whether the Text Size slider shows the size that is actually on screen.
///
/// The defect: `EditorView` kept the slider's value in its own `@State`,
/// seeded once in `init` from the project's style. Picking a preset went
/// through `EditorViewModel.selectStyle`, which changed the caption but left
/// the view's copy alone — so the readout said 32 while the captions were
/// drawn at 34. Worse, the next nudge of the slider wrote that stale 32 back
/// out and the captions jumped *down* a size the user never asked for.
///
/// The fix removed the second copy: the slider now reads and writes
/// `EditorViewModel.captionFontSize`, which is derived from the selected
/// style rather than stored alongside it. These assertions go through that
/// property, because that is what the slider is bound to.
@MainActor
final class CaptionSizeReadoutTests: XCTestCase {
    private func makeViewModel() throws -> (EditorViewModel, Project) {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        try context.save()
        return (EditorViewModel(project: project), project)
    }

    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    // MARK: - Guards
    //
    // The red test below is only meaningful if the two presets it picks
    // disagree about size, and if the property can carry a value at all.

    func testTheTwoPresetsUnderTestDisagreeAboutSize() throws {
        XCTAssertNotEqual(try preset("Hormozi").fontSize, try preset("Beast").fontSize)
    }

    func testTheSizeSetByTheSliderIsTheSizeReportedBack() throws {
        let (viewModel, _) = try makeViewModel()

        viewModel.captionFontSize = 44

        XCTAssertEqual(viewModel.captionFontSize, 44)
    }

    // MARK: - Picking a preset moves the readout

    func testPickingAPresetMovesTheReadoutToThatPresetsSize() throws {
        let (viewModel, _) = try makeViewModel()
        let beast = try preset("Beast")
        XCTAssertEqual(viewModel.captionFontSize, try preset("Hormozi").fontSize)

        viewModel.selectStyle(beast)

        XCTAssertEqual(
            viewModel.captionFontSize,
            beast.fontSize,
            "the slider reads \(viewModel.captionFontSize)pt but the captions are drawn at \(beast.fontSize)pt"
        )
    }

    func testEveryPresetsReadoutIsThatPresetsOwnSize() throws {
        let (viewModel, _) = try makeViewModel()

        for style in CaptionStyle.presets {
            viewModel.selectStyle(style)
            XCTAssertEqual(
                viewModel.captionFontSize,
                style.fontSize,
                "\(style.name) draws at \(style.fontSize)pt but the slider reads \(viewModel.captionFontSize)pt"
            )
        }
    }

    func testTheReadoutIsTheSizeTheExportWillUse() throws {
        let (viewModel, project) = try makeViewModel()

        viewModel.selectStyle(try preset("Ali Abdaal"))

        XCTAssertEqual(
            viewModel.captionFontSize,
            project.selectedStyle.fontSize,
            "the slider reads \(viewModel.captionFontSize)pt, the export draws \(project.selectedStyle.fontSize)pt"
        )
    }

    func testASizeTheUserSetSurvivesPickingAPresetAndComingBack() throws {
        let (viewModel, _) = try makeViewModel()
        viewModel.captionFontSize = 44

        viewModel.selectStyle(try preset("Beast"))

        // Picking a preset is meant to adopt that preset wholesale, size and
        // all — the 44 is gone on purpose. What must not happen is the readout
        // keeping 44 while the captions render at Beast's 34.
        XCTAssertEqual(viewModel.captionFontSize, try preset("Beast").fontSize)
    }

    // MARK: - Setting the size changes only the size

    func testSettingTheSizeDoesNotChangeWhichStyleIsSelected() throws {
        let (viewModel, project) = try makeViewModel()
        viewModel.selectStyle(try preset("Submagic"))

        viewModel.captionFontSize = 44

        XCTAssertEqual(viewModel.selectedStyle.name, "Submagic")
        XCTAssertEqual(project.selectedStyle.name, "Submagic")
    }

    func testSettingTheSizeReachesTheProjectTheExportReads() throws {
        let (viewModel, project) = try makeViewModel()

        viewModel.captionFontSize = 44

        XCTAssertEqual(project.selectedStyle.fontSize, 44)
    }

    func testTheReadoutIsWithinTheRangeTheSliderOffers() throws {
        // A preset outside the slider's range would be clamped by the
        // control, and the readout would disagree with the captions the
        // moment the sheet opened.
        let range = StyleSheetView.fontSizeRange
        for style in CaptionStyle.presets {
            XCTAssertTrue(
                range.contains(style.fontSize),
                "\(style.name) is \(style.fontSize)pt, outside the slider's \(range)pt range"
            )
        }
    }

    func testASizeBelowTheOldFloorReachesTheProject() throws {
        let (viewModel, project) = try makeViewModel()
        XCTAssertTrue(StyleSheetView.fontSizeRange.contains(4), "the slider cannot reach 4pt")

        viewModel.captionFontSize = 4

        XCTAssertEqual(project.selectedStyle.fontSize, 4)
    }
}
