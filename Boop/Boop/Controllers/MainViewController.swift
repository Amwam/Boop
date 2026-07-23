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

    override func viewDidLoad() {
        super.viewDidLoad()

        #if APPSTORE

        checkUpdateMenuItem.isHidden = true

        #endif

        editorView.applyTheme(for: view.effectiveAppearance)
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
