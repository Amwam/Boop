//
//  LanguageStatusBar.swift
//  Boop
//
//  A thin bar shown along the bottom of the window. It displays the language
//  the editor is currently using and lets the user override the auto-detected
//  guess (or reset back to "Auto"). Built entirely in code and added to the
//  window by MainViewController.
//

import Cocoa
import CodeEditLanguages

final class LanguageStatusBar: NSView {

    /// Called when the user picks a specific language from the menu.
    var onSelectLanguage: ((CodeLanguage) -> Void)?
    /// Called when the user picks the "Auto" entry.
    var onSelectAuto: (() -> Void)?

    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)

    /// Languages offered in the override menu, sorted by display name.
    private let languages: [CodeLanguage] = CodeLanguage.allLanguages
        .sorted { displayName(for: $0) < displayName(for: $1) }

    /// The first menu item, whose title we relabel to reflect the auto guess.
    private var autoItem: NSMenuItem!
    /// Menu items keyed by language, so we can select the matching one.
    private var itemsByLanguage: [TreeSitterLanguage: NSMenuItem] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true

        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.bezelStyle = .inline
        popUp.isBordered = false
        popUp.controlSize = .small
        popUp.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        popUp.target = self
        popUp.action = #selector(selectionChanged)
        buildMenu()

        addSubview(popUp)
        NSLayoutConstraint.activate([
            popUp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            popUp.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func buildMenu() {
        let menu = NSMenu()

        autoItem = NSMenuItem(title: "Auto", action: nil, keyEquivalent: "")
        autoItem.tag = -1
        menu.addItem(autoItem)
        menu.addItem(.separator())

        for (index, language) in languages.enumerated() {
            let item = NSMenuItem(title: Self.displayName(for: language),
                                  action: nil, keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
            itemsByLanguage[language.id] = item
        }

        popUp.menu = menu
    }

    @objc private func selectionChanged() {
        guard let selected = popUp.selectedItem else { return }
        if selected.tag == -1 {
            onSelectAuto?()
        } else if languages.indices.contains(selected.tag) {
            onSelectLanguage?(languages[selected.tag])
        }
    }

    /// Reflect the editor's current language/mode in the bar.
    func update(language: CodeLanguage, isAuto: Bool) {
        if isAuto {
            // Keep "Auto" selected, but show what was detected alongside it.
            if language.id == CodeLanguage.default.id {
                autoItem.title = "Auto"
            } else {
                autoItem.title = "Auto · \(Self.displayName(for: language))"
            }
            popUp.select(autoItem)
        } else {
            autoItem.title = "Auto"
            if let item = itemsByLanguage[language.id] {
                popUp.select(item)
            }
        }
    }

    /// A human-readable name for a language, since `CodeLanguage` has none.
    static func displayName(for language: CodeLanguage) -> String {
        let special: [TreeSitterLanguage: String] = [
            .cpp: "C++", .cSharp: "C#", .objc: "Objective-C",
            .css: "CSS", .html: "HTML", .json: "JSON", .jsdoc: "JSDoc",
            .sql: "SQL", .php: "PHP", .jsx: "JSX", .tsx: "TSX",
            .goMod: "Go Mod", .yaml: "YAML", .toml: "TOML", .ocaml: "OCaml",
            .ocamlInterface: "OCaml Interface", .javascript: "JavaScript",
            .typescript: "TypeScript", .plainText: "Plain Text",
            .markdownInline: "Markdown (Inline)"
        ]
        if let name = special[language.id] {
            return name
        }
        let raw = language.id.rawValue
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
