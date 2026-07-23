//
//  CodeEditorView.swift
//  Boop
//
//  A thin Boop-shaped facade around CodeEditSourceEditor's `TextViewController`.
//  Hosts the controller's view, exposes a simple text/selection API, and forwards
//  change notifications. Instantiated from the XIB.
//

import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages

/// Internal coordinator that forwards `TextViewController` change callbacks to the
/// facade's closures.
private final class EditorChangeCoordinator: CodeEditSourceEditor.TextViewCoordinator {
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: (([NSRange]) -> Void)?

    func prepareCoordinator(controller: TextViewController) {}

    func textViewDidChangeText(controller: TextViewController) {
        onTextChange?(controller.text)
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        let ranges = newPositions.map { $0.range }.sorted { $0.location < $1.location }
        onSelectionChange?(ranges)
    }
}

final class CodeEditorView: NSView {

    private var controller: TextViewController!
    private let changeCoordinator = EditorChangeCoordinator()
    private var textChangeDebounceWorkItem: DispatchWorkItem?

    /// Underlying CodeEditTextView text view — for direct manipulation and for
    /// `window.makeFirstResponder(_:)`. NOT an NSTextView.
    var textView: CodeEditTextView.TextView {
        controller.textView
    }

    /// Full document contents.
    var text: String {
        get { controller.text }
        set { controller.setText(newValue) }
    }

    /// Primary selection (first cursor).
    var selectedRange: NSRange {
        get { selectedRanges.first ?? NSRange(location: 0, length: 0) }
        set { selectedRanges = [newValue] }
    }

    /// All selections (multi-cursor), ordered by location.
    var selectedRanges: [NSRange] {
        get {
            textView.selectionManager.textSelections
                .map { $0.range }
                .sorted { $0.location < $1.location }
        }
        set {
            textView.selectionManager.setSelectedRanges(newValue)
        }
    }

    /// Fired after text changes.
    var onTextChange: ((String) -> Void)?

    /// Fired after selection/cursor changes. Ranges ordered by location.
    var onSelectionChange: (([NSRange]) -> Void)?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpController()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpController()
    }

    private func setUpController() {
        changeCoordinator.onTextChange = { [weak self] text in
            self?.handleTextChange(text)
        }
        changeCoordinator.onSelectionChange = { [weak self] ranges in
            self?.onSelectionChange?(ranges)
        }

        let appearance = effectiveAppearance
        controller = TextViewController(
            string: "",
            language: .default,
            configuration: SourceEditorConfiguration(
                appearance: .init(
                    theme: BoopEditorTheme.theme(for: appearance),
                    font: NSFont(name: "SFMono-Regular", size: 15)
                        ?? .monospacedSystemFont(ofSize: 15, weight: .regular),
                    wrapLines: true
                ),
                behavior: .init(indentOption: .spaces(count: 4))
            ),
            cursorPositions: [CursorPosition(line: 1, column: 1)],
            coordinators: [changeCoordinator]
        )

        addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func handleTextChange(_ text: String) {
        onTextChange?(text)

        textChangeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setLanguage(LanguageDetector.detect(from: text))
        }
        textChangeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    /// Undo-grouped, multi-range replace. Applies all replacements as a single undo step.
    func replace(ranges: [NSRange], with values: [String]) {
        guard ranges.count == values.count, !ranges.isEmpty else { return }

        // Process from the end of the document backwards so that earlier ranges are
        // unaffected by replacements made later in the document (no offset math needed).
        let pairs = zip(ranges, values).sorted { $0.0.location > $1.0.location }

        textView.undoManager?.beginUndoGrouping()
        for (range, value) in pairs {
            textView.replaceCharacters(in: range, with: value)
        }
        textView.undoManager?.endUndoGrouping()
    }

    /// Set syntax-highlighting language (drives tree-sitter). Safe to call repeatedly.
    func setLanguage(_ language: CodeLanguage) {
        guard controller.language.id != language.id else { return }
        controller.language = language
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme(for: effectiveAppearance)
    }

    /// Apply Boop's light/dark theme for the given appearance.
    func applyTheme(for appearance: NSAppearance) {
        // `viewDidChangeEffectiveAppearance` can fire during `super.init(coder:)`,
        // before `setUpController()` has assigned `controller`. Bail out until then;
        // `setUpController()` builds the theme for the current appearance itself.
        guard controller != nil else { return }
        var configuration = controller.configuration
        configuration.appearance.theme = BoopEditorTheme.theme(for: appearance)
        controller.configuration = configuration
    }
}
