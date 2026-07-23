//
//  ScriptManager.swift
//  Yup
//
//  Created by Ivan on 1/15/17.
//  Copyright © 2017 OKatBest. All rights reserved.
//

import Cocoa
import Fuse


class ScriptManager: NSObject {
    
    
    
    static let userPreferencesPathKey = "scriptsFolderPath"
    static let userPreferencesDataKey = "scriptsFolderData"
    
    // This probably does not belong here.
    @IBOutlet weak var statusView: StatusView!
    
    let fuse = Fuse(threshold: 0.2)
    var scripts = [Script]()
    
    let currentAPIVersion = 1.0
    
    var lastScript: Script?
    
    override init() {
        super.init()
        
        loadDefaultScripts()
        loadUserScripts()
    }
    

    static func setBookmarkData(url: URL) throws {
        
        let data = try url.bookmarkData(options: NSURL.BookmarkCreationOptions.withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        
        UserDefaults.standard.set(data, forKey: ScriptManager.userPreferencesDataKey)
    }
    
    /// Load built in scripts
    func loadDefaultScripts(){
        let urls = Bundle.main.urls(forResourcesWithExtension: "js", subdirectory: "scripts")
        
        urls?.forEach { script in
            loadScript(url: script, builtIn: true)
        }
    }
    
    
    /// Load user scripts
    func loadUserScripts(){
        
        do {
            
            guard let url = try ScriptManager.getBookmarkURL() else {
                return
            }
            
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            urls.forEach { url in
                guard url.path.hasSuffix(".js") else {
                    return
                }
                loadScript(url: url, builtIn: false)
            }
            
        }
        catch let error {
            print(error)
            return
        }
    }
    
    /// Parses a script file
    private func loadScript(url: URL, builtIn: Bool){
        do{
            let script = try String(contentsOf: url)
            
            // This is inspired by the ISF file format by Vidvox
            // Thanks to them for the idea and their awesome work
            
            guard
                let openComment = script.range(of: "/**"),
                let closeComment = script.range(of: "**/")
                else {
                    throw NSError()
            }
            
            let meta = script[openComment.upperBound..<closeComment.lowerBound]
            
            let json = try JSONSerialization.jsonObject(with: meta.data(using: .utf8)!, options: .allowFragments) as! [String: Any]
            
            let scriptObject = Script(url: url, script: script, parameters: json, builtIn: builtIn, delegate: self)
            
            scripts.append(scriptObject)
            
            
        } catch {
            print("Unable to load ", url)
        }
    }
    
    func search(_ query: String) -> [Script] {
        
        
        guard query.count < 20 else {
            // If the query is too long let's just ignore it.
            // It's probably the user pasting the wrong thing
            // in the search box by accident which overwhelms
            // fuse and crashes the app. Whoops!
            
            return []
        }
        
        guard query != "*" else {
            
            return scripts.sorted { left, right in
                left.name ?? "" < right.name ?? ""
            }
        }
        
        let results = fuse.search(query, in: scripts)
        
        return results.filter { result in
            result.score < 0.4 // Filter low quality results
        }.sorted { left, right in
            let leftScore = left.score - (scripts[left.index].bias ?? 0)
            let rightScore = right.score - (scripts[right.index].bias ?? 0)
            return leftScore < rightScore
        }.map { result in
            scripts[result.index]
        }
    }
    
    func runScript(_ script: Script, into editor: CodeEditorView) {

        let fullText = editor.text

        lastScript = script

        let ranges = editor.selectedRanges

        guard ranges.reduce(0, { $0 + $1.length }) > 0 else {

            let insertPosition = ranges.first?.location
            let result = runScript(script, fullText: fullText, insertIndex: insertPosition)
            // No selection, run on full text

            let unicodeSafeFullTextLength = (editor.text as NSString).length
            replaceText(ranges: [NSRange(location: 0, length: unicodeSafeFullTextLength)], values: [result], editor: editor)

            return
        }

        // Fun fact: You can have multi selections! Which means we need to disable
        // the ability to edit `fullText` while in selection mode, otherwise the
        // some scripts may accidentally run multiple time over the full text.

        let values = ranges.map {
            range -> String in

            let value = (fullText as NSString).substring(with: range)

            return runScript(script, selection: value, fullText: fullText)

        }

        replaceText(ranges: ranges, values: values, editor: editor)


    }

    private func replaceText(ranges: [NSRange], values: [String], editor: CodeEditorView) {
        // `editor.replace(ranges:with:)` is undo-grouped and already offsets
        // later ranges by earlier replacements' length deltas internally, so
        // we just pass the original ranges + values straight through.
        editor.replace(ranges: ranges, with: values)
    }
    
    func runScript(_ script: Script, selection: String? = nil, fullText: String, insertIndex: Int? = nil) -> String {
        let scriptExecution = ScriptExecution(selection: selection, fullText: fullText, script: script, insertIndex: insertIndex)
        
        self.statusView.setStatus(.normal)
        script.run(with: scriptExecution)
        
        return scriptExecution.text ?? ""
    }
    
    func runScriptAgain(editor: CodeEditorView) {
        guard let script = lastScript else {
            NSSound.beep()
            return
        }
        
        runScript(script, into: editor)
    }
    
    func reloadScripts() {
        lastScript = nil
        scripts.removeAll()
        loadDefaultScripts()
        loadUserScripts()
        
        statusView.setStatus(.success("Reloaded Scripts"))
    }
    
    static func getBookmarkURL() throws -> URL? {
        
        guard let data = UserDefaults.standard.data(forKey: ScriptManager.userPreferencesDataKey) else {
            // No user path specified, abbandon ship!
            return nil
        }
        
        var isBookmarkStale = false
                  
        let url = try URL.init(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isBookmarkStale)

        if(isBookmarkStale) {
            try ScriptManager.setBookmarkData(url: url)
        }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        
        return url
    }
    
}

extension ScriptManager: ScriptDelegate {
    func onScriptError(message: String) {
        self.statusView.setStatus(.error(message))
    }
    
    func onScriptInfo(message: String) {
        self.statusView.setStatus(.info(message))
    }
    
    
}
