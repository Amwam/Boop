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

/// Whether the editor's language is chosen automatically by the detector, or
/// pinned to a specific language by the user.
enum LanguageMode: Equatable {
    case auto
    case manual(CodeLanguage)
}

final class CodeEditorView: NSView {

    private var controller: TextViewController!
    private let changeCoordinator = EditorChangeCoordinator()
    private var textChangeDebounceWorkItem: DispatchWorkItem?

    /// UserDefaults key persisting the user's language choice across launches.
    /// Stores `"auto"` or a `TreeSitterLanguage` raw value (e.g. `"swift"`).
    private static let languageModeDefaultsKey = "editorLanguageMode"

    /// Current language mode: `.auto` (detector decides) or `.manual(...)`.
    private(set) var languageMode: LanguageMode = .auto

    /// Last language the detector produced, so resetting to auto can re-apply it.
    private var lastDetectedLanguage: CodeLanguage = .default

    /// Fired on the main thread whenever the applied language changes, with the
    /// current language and whether we're in auto mode. Drives the status bar.
    var onLanguageChange: ((_ language: CodeLanguage, _ isAuto: Bool) -> Void)?

    /// Language currently applied to the editor.
    var currentLanguage: CodeLanguage { controller.language }

    /// Whether the editor is currently letting the detector choose the language.
    var isAutoLanguage: Bool {
        if case .auto = languageMode { return true }
        return false
    }

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

        restorePersistedLanguageMode()
    }

    private func handleTextChange(_ text: String) {
        onTextChange?(text)

        // Debounce, then detect on a background queue so typing never waits on
        // detection. The result is applied back on the main thread (UI work).
        textChangeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            let detected = LanguageDetector.detect(from: text)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lastDetectedLanguage = detected
                // Only auto-apply when the user hasn't pinned a language.
                guard self.isAutoLanguage else { return }
                self.setLanguage(detected)
                self.onLanguageChange?(detected, true)
            }
        }
        textChangeDebounceWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    // MARK: - Language mode (auto vs. manual override)

    /// Pin the editor to a specific language, ignoring the detector until reset.
    func overrideLanguage(_ language: CodeLanguage) {
        languageMode = .manual(language)
        persistLanguageMode()
        setLanguage(language)
        onLanguageChange?(language, false)
    }

    /// Hand control back to the detector and re-detect the current text now.
    func resetToAutoLanguage() {
        languageMode = .auto
        persistLanguageMode()

        // Apply the most recent guess immediately for a responsive UI...
        setLanguage(lastDetectedLanguage)
        onLanguageChange?(lastDetectedLanguage, true)

        // ...then re-run detection on the current text in the background in case
        // it changed while a manual language was pinned.
        let text = self.text
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let detected = LanguageDetector.detect(from: text)
            DispatchQueue.main.async {
                guard let self = self, self.isAutoLanguage else { return }
                self.lastDetectedLanguage = detected
                self.setLanguage(detected)
                self.onLanguageChange?(detected, true)
            }
        }
    }

    private func persistLanguageMode() {
        let value: String
        switch languageMode {
        case .auto:
            value = "auto"
        case .manual(let language):
            value = language.id.rawValue
        }
        UserDefaults.standard.set(value, forKey: Self.languageModeDefaultsKey)
    }

    private func restorePersistedLanguageMode() {
        guard let value = UserDefaults.standard.string(forKey: Self.languageModeDefaultsKey),
              value != "auto",
              let tsLanguage = TreeSitterLanguage(rawValue: value),
              let language = CodeLanguage.allLanguages.first(where: { $0.id == tsLanguage }) else {
            return
        }
        languageMode = .manual(language)
        setLanguage(language)
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
