//
//  MainViewController.swift
//  Boop
//
//  Created by Ivan on 1/26/19.
//  Copyright © 2019 OKatBest. All rights reserved.
//

import Cocoa

class MainViewController: NSViewController {

    @IBOutlet weak var editorView: CodeEditorView!
    @IBOutlet weak var updateBuddy: UpdateBuddy!
    @IBOutlet weak var checkUpdateMenuItem: NSMenuItem!

    private let languageStatusBar = LanguageStatusBar()

    override func viewDidLoad() {
        super.viewDidLoad()

        #if APPSTORE

        checkUpdateMenuItem.isHidden = true

        #endif

        editorView.applyTheme(for: view.effectiveAppearance)
        setUpLanguageStatusBar()
    }

    /// Adds the bottom language bar and connects it to the editor. The editor
    /// (`self.view`) fills the window; we tuck the bar under it and re-pin the
    /// editor's bottom edge so text isn't hidden behind the bar.
    private func setUpLanguageStatusBar() {
        guard let container = editorView.superview else { return }

        // The editor's bottom is pinned to the container in the XIB. Release it
        // so we can pin the editor above the new bar instead.
        for constraint in container.constraints where
            (constraint.firstItem === editorView && constraint.firstAttribute == .bottom) ||
            (constraint.secondItem === editorView && constraint.secondAttribute == .bottom) {
            constraint.isActive = false
        }

        languageStatusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(languageStatusBar, positioned: .above, relativeTo: editorView)

        NSLayoutConstraint.activate([
            languageStatusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            languageStatusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            languageStatusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            languageStatusBar.heightAnchor.constraint(equalToConstant: 24),
            editorView.bottomAnchor.constraint(equalTo: languageStatusBar.topAnchor)
        ])

        languageStatusBar.onSelectLanguage = { [weak self] language in
            self?.editorView.overrideLanguage(language)
        }
        languageStatusBar.onSelectAuto = { [weak self] in
            self?.editorView.resetToAutoLanguage()
        }
        editorView.onLanguageChange = { [weak self] language, isAuto in
            self?.languageStatusBar.update(language: language, isAuto: isAuto)
        }

        // Seed the bar with the editor's current state.
        languageStatusBar.update(language: editorView.currentLanguage,
                                 isAuto: editorView.isAutoLanguage)
    }

    @IBAction func openHelp(_ sender: Any) {
        open(url: "https://boop.okat.best/docs/")
    }
    
    
    @IBAction func openScripts(_ sender: Any) {
        open(url: "https://boop.okat.best/scripts/")
    }
    
    
    func open(url: String) {
        guard let url = URL(string: url) else {
            assertionFailure("Could not generate help URL.")
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func clear(_ sender: Any) {
        editorView.text = ""
    }


    @IBAction func checkForUpdates(_ sender: Any) {
        updateBuddy.check()
    }
}
