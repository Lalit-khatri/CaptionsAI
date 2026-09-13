@testable import CaptionsAI
import SwiftData
import XCTest

/// Whether the caption size the user sets is the size that gets used.
///
/// The defect: the Text Size slider mutated a copy of the style held by the
/// view model, and `selectStyle` persisted only the style's *name*.
/// `Project.selectedStyle` rebuilt a pristine preset from that name — and that
/// is what the export renderer reads. Drag to 48 pt, the preview obeys, the
/// exported file ships the preset's 32 pt, and the slider's value is gone at
/// the next launch.
///
/// The assertions go through the two properties the app actually reads:
/// `EditorViewModel.selectedStyle` (the preview, via `CaptionOverlay`) and
/// `Project.selectedStyle` (the export, via `ExportView`). The invariant is
/// that they agree.
@MainActor
final class StyleSizeTests: XCTestCase {
    /// A size no preset uses, so a passing assertion cannot be a preset's own
    /// value sneaking through. The presets sit between 24 and 34 pt.
    private let chosenSize: CGFloat = 48

    private func makeProject(in context: ModelContext) throws -> Project {
        let project = Project(name: "Test", videoURL: TestSupport.placeholderVideoURL)
        context.insert(project)
        try context.save()
        return project
    }

    private func preset(_ name: String) throws -> CaptionStyle {
        try XCTUnwrap(CaptionStyle.presets.first { $0.name == name })
    }

    /// What the Text Size slider does: write through
    /// `EditorViewModel.captionFontSize`, which the sheet is bound to.
    private func dragTextSize(to size: CGFloat, on viewModel: EditorViewModel) {
        viewModel.captionFontSize = size
    }

    // MARK: - The preview and the export agree

    func testTheSizeTheUserDragsToIsTheSizeExportDraws() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)
        let viewModel = EditorViewModel(project: project)

        dragTextSize(to: chosenSize, on: viewModel)

        XCTAssertEqual(project.selectedStyle.fontSize, chosenSize)
    }

    func testThePreviewAndTheExportUseTheSameSize() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)
        let viewModel = EditorViewModel(project: project)

        dragTextSize(to: chosenSize, on: viewModel)

        XCTAssertEqual(
            viewModel.selectedStyle.fontSize,
            project.selectedStyle.fontSize,
            "the preview draws \(viewModel.selectedStyle.fontSize)pt, the export draws \(project.selectedStyle.fontSize)pt"
        )
    }

    // MARK: - It sticks

    func testTheSizeSurvivesRelaunch() throws {
        let container = try TestSupport.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context)
        dragTextSize(to: chosenSize, on: EditorViewModel(project: project))
        try context.save()

        let reopened = ModelContext(container)
        let projects = try reopened.fetch(FetchDescriptor<Project>())
        let reloaded = try XCTUnwrap(projects.first)

        XCTAssertEqual(reloaded.selectedStyle.fontSize, chosenSize)
    }

    func testReopeningTheEditorShowsTheSizeTheUserSet() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)
        dragTextSize(to: chosenSize, on: EditorViewModel(project: project))

        let reopenedEditor = EditorViewModel(project: project)

        XCTAssertEqual(reopenedEditor.selectedStyle.fontSize, chosenSize)
    }

    // MARK: - Everything else about a style is untouched

    func testAProjectWithNoSizeEditUsesThePresetsOwnSize() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)

        XCTAssertNil(project.captionFontSize)
        XCTAssertEqual(project.selectedStyle.fontSize, try preset("Hormozi").fontSize)
    }

    func testPickingAPresetAdoptsThatPresetsSizeAndLook() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)
        let viewModel = EditorViewModel(project: project)
        dragTextSize(to: chosenSize, on: viewModel)

        let beast = try preset("Beast")
        viewModel.selectStyle(beast)

        XCTAssertEqual(project.selectedStyle.name, "Beast")
        XCTAssertEqual(project.selectedStyle.fontSize, beast.fontSize)
        XCTAssertEqual(project.selectedStyle.highlightColor, beast.highlightColor)
        XCTAssertEqual(project.selectedStyle.animation, beast.animation)
    }

    func testTheSizeOverrideChangesNothingElseAboutTheStyle() throws {
        let context = ModelContext(try TestSupport.makeInMemoryContainer())
        let project = try makeProject(in: context)
        dragTextSize(to: chosenSize, on: EditorViewModel(project: project))

        var expected = try preset("Hormozi")
        expected.fontSize = chosenSize

        XCTAssertEqual(project.selectedStyle, expected)
    }
}
