//
//  LanguageDetector.swift
//  Boop
//
//  Cheap, content-based language detection for CodeEditSourceEditor.
//  Boop has no filenames to go on, so detection is purely heuristic: it looks
//  only at a bounded prefix of the document and either matches a reliable
//  structural marker (shebang, `<?php`, valid JSON, ...) or scores the text
//  against per-language keyword/pattern signatures, returning the best match
//  when confident and `.default` when not. Called from the editor's debounced,
//  background onTextChange — keep it fast.
//

import Foundation
import CodeEditLanguages

enum LanguageDetector {

    /// Bound how much of the document we inspect. Detection only ever needs
    /// a small prefix, so this keeps the scan cheap even for huge documents.
    private static let prefixLength = 2048

    /// Minimum score a language must reach before we trust the guess. Below
    /// this we stay on `.default` (plain text) rather than misclassify.
    private static let scoreThreshold = 3.0

    static func detect(from text: String) -> CodeLanguage {
        let prefix = String(text.prefix(prefixLength))
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty else { return .default }

        let firstLine = firstNonEmptyLine(in: prefix)

        // Reliable structural markers win outright — no need to score.
        if let language = structuralMatch(prefix: prefix,
                                          trimmedPrefix: trimmedPrefix,
                                          firstLine: firstLine,
                                          fullText: text) {
            return language
        }

        // Otherwise, score the prefix against every language signature.
        return scoredMatch(in: prefix) ?? .default
    }

    // MARK: - Structural (high-confidence) matches

    private static func structuralMatch(prefix: String,
                                        trimmedPrefix: String,
                                        firstLine: String,
                                        fullText: String) -> CodeLanguage? {
        // Shebang
        if firstLine.hasPrefix("#!") {
            if firstLine.contains("bash") || firstLine.contains("/sh") || firstLine.contains("zsh") {
                return .bash
            }
            if firstLine.contains("python") { return .python }
            if firstLine.contains("node") { return .javascript }
            if firstLine.contains("ruby") { return .ruby }
            if firstLine.contains("perl") { return .perl }
        }

        // Unambiguous leading markers
        if trimmedPrefix.hasPrefix("<?php") { return .php }

        let lowerTrimmed = trimmedPrefix.lowercased()
        if lowerTrimmed.hasPrefix("<!doctype html") || lowerTrimmed.hasPrefix("<html") {
            return .html
        }
        if lowerTrimmed.hasPrefix("<?xml") {
            // No dedicated XML language is registered; HTML's markup grammar
            // is the closest available fit.
            return .html
        }

        // JSON: only trust it if the whole document actually parses.
        if trimmedPrefix.hasPrefix("{") || trimmedPrefix.hasPrefix("[") {
            if let data = fullText.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) != nil {
                return .json
            }
        }

        // YAML front-matter delimiter.
        if prefix.hasPrefix("---\n") || prefix.hasPrefix("---\r\n") {
            return .yaml
        }

        return nil
    }

    // MARK: - Weighted scoring

    private static func scoredMatch(in prefix: String) -> CodeLanguage? {
        let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)

        var best: (language: CodeLanguage, score: Double)?
        for rule in rules {
            var score = 0.0
            for signal in rule.signals where signal.regex.firstMatch(in: prefix, range: range) != nil {
                score += signal.weight
            }
            // `>` (not `>=`) keeps the earlier, more specific rule on ties.
            if score >= scoreThreshold, score > (best?.score ?? 0) {
                best = (rule.language, score)
            }
        }
        return best?.language
    }

    // MARK: - Helpers

    private static func firstNonEmptyLine(in text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}

// MARK: - Language signatures

private extension LanguageDetector {

    struct Signal {
        let regex: NSRegularExpression
        let weight: Double
    }

    struct Rule {
        let language: CodeLanguage
        let signals: [Signal]
    }

    /// Compile a pattern. `^`/`$` match per line so YAML/Markdown line anchors work.
    static func rx(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        // Patterns are compile-time constants; a failure here is a programmer error.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func signal(_ pattern: String, _ weight: Double, caseInsensitive: Bool = false) -> Signal {
        Signal(regex: rx(pattern, caseInsensitive: caseInsensitive), weight: weight)
    }

    /// Ordered most-specific first: on a score tie, the earlier rule wins.
    static let rules: [Rule] = [
        Rule(language: .swift, signals: [
            signal(#"\bimport\s+(Foundation|UIKit|SwiftUI|Cocoa|AppKit|Combine)\b"#, 3),
            signal(#"\bfunc\s+\w+\s*\("#, 2),
            signal(#"\b(guard|if)\s+let\b"#, 2),
            signal(#"@(objc|IBOutlet|IBAction|State|Published|escaping)\b"#, 2),
            signal(#"\b(let|var)\s+\w+\s*[:=]"#, 1),
            signal(#"->\s*\w"#, 1),
        ]),
        Rule(language: .go, signals: [
            signal(#"\bfmt\.\w+"#, 3),
            signal(#"\btype\s+\w+\s+struct\b"#, 3),
            signal(#"\bpackage\s+\w+"#, 2),
            signal(#"\bfunc\s+(\(\s*\w+\s+\*?\w+\s*\)\s+)?\w+\s*\("#, 2),
            signal(#":="#, 2),
            signal(#"\bimport\s+\("#, 1),
        ]),
        Rule(language: .rust, signals: [
            signal(#"\b(println|panic|format|vec|write)!"#, 3),
            signal(#"\blet\s+mut\b"#, 3),
            signal(#"\bfn\s+\w+\s*\("#, 2),
            signal(#"\buse\s+\w+::"#, 2),
            signal(#"\b(pub\s+)?(fn|struct|enum|impl|trait)\b"#, 2),
            signal(#"->\s*\w"#, 1),
        ]),
        Rule(language: .python, signals: [
            signal(#"\bdef\s+\w+\s*\([^)]*\)\s*:"#, 3),
            signal(#"\belif\b"#, 3),
            signal(#"\bfrom\s+[\w.]+\s+import\b"#, 3),
            signal(#"\b__\w+__\b"#, 2),
            signal(#"\bprint\s*\("#, 1),
            signal(#"\bimport\s+\w+"#, 1),
            signal(#"\b(self|None|True|False|lambda)\b"#, 1),
        ]),
        Rule(language: .ruby, signals: [
            signal(#"\bputs\b"#, 3),
            signal(#"\brequire(_relative)?\s+['\"]"#, 2),
            signal(#"\bend\b"#, 2),
            signal(#"\bdo\s*\|"#, 2),
            signal(#"\bdef\s+\w+"#, 1),
            signal(#"@\w+"#, 1),
            signal(#"\bnil\b|\.each\b"#, 1),
        ]),
        Rule(language: .typescript, signals: [
            signal(#"\binterface\s+\w+"#, 3),
            signal(#"\btype\s+\w+\s*="#, 2),
            signal(#":\s*(string|number|boolean|any|void|unknown|never)\b"#, 2),
            signal(#"\benum\s+\w+"#, 2),
            signal(#"\bexport\s+(default\s+)?(class|function|const|interface|type|enum)\b"#, 1),
            signal(#"=>"#, 1),
        ]),
        Rule(language: .javascript, signals: [
            signal(#"\bconsole\.\w+"#, 3),
            signal(#"\b(require\s*\(|module\.exports\b)"#, 2),
            signal(#"\bfunction\s*\*?\s*\w*\s*\("#, 2),
            signal(#"\b(document|window)\."#, 2),
            signal(#"\b(const|let|var)\s+\w+\s*="#, 2),
            signal(#"=>"#, 1),
            signal(#"===|!=="#, 1),
        ]),
        Rule(language: .java, signals: [
            signal(#"\bpublic\s+static\s+void\s+main\b"#, 3),
            signal(#"\bSystem\.out\."#, 3),
            signal(#"\bimport\s+java"#, 3),
            signal(#"\bpublic\s+(final\s+|abstract\s+)?class\b"#, 3),
            signal(#"\b(public|private|protected)\s+\w+\s+\w+\s*\("#, 1),
        ]),
        Rule(language: .cpp, signals: [
            signal(#"#include\s*<(iostream|vector|string|map|set|algorithm|memory)>"#, 3),
            signal(#"\bstd::\w+"#, 3),
            signal(#"\b(cout|cin|endl)\b"#, 3),
            signal(#"\busing\s+namespace\b"#, 3),
            signal(#"\btemplate\s*<"#, 2),
        ]),
        Rule(language: .c, signals: [
            signal(#"#include\s*<\w+\.h>"#, 3),
            signal(#"\bint\s+main\s*\("#, 2),
            signal(#"\b(printf|scanf|malloc|free|sizeof)\b"#, 2),
            signal(#"\b(struct|typedef|void)\b"#, 1),
        ]),
        Rule(language: .php, signals: [
            signal(#"<\?php"#, 3),
            signal(#"\becho\b"#, 1),
            signal(#"\$\w+\s*="#, 1),
            signal(#"->\w+\s*\("#, 1),
            signal(#"\bfunction\s+\w+\s*\("#, 1),
        ]),
        Rule(language: .sql, signals: [
            signal(#"\bSELECT\b[\s\S]*\bFROM\b"#, 3, caseInsensitive: true),
            signal(#"\bINSERT\s+INTO\b"#, 3, caseInsensitive: true),
            signal(#"\bCREATE\s+(TABLE|DATABASE|INDEX|VIEW)\b"#, 3, caseInsensitive: true),
            signal(#"\bUPDATE\b[\s\S]*\bSET\b"#, 3, caseInsensitive: true),
            signal(#"\bDELETE\s+FROM\b"#, 3, caseInsensitive: true),
            signal(#"\b(WHERE|JOIN|GROUP\s+BY|ORDER\s+BY)\b"#, 1, caseInsensitive: true),
        ]),
        Rule(language: .bash, signals: [
            signal(#"\b(then|fi|done|elif|esac)\b"#, 2),
            signal(#"\bif\s+\[|\[\["#, 2),
            signal(#"\$\(|\$\{"#, 1),
            signal(#"\becho\s+"#, 1),
            signal(#"\b(for\s+\w+\s+in|while|case)\b"#, 1),
            signal(#"\bexport\s+\w+="#, 1),
        ]),
        Rule(language: .css, signals: [
            signal(#"@(media|import|keyframes|font-face)\b"#, 3),
            signal(#"[.#][\w-]+\s*\{"#, 2),
            signal(#":\s*#[0-9a-fA-F]{3,8}\b"#, 2),
            signal(#"\b\d+(px|rem|em|vh|vw|pt)\b"#, 1),
            signal(#"\{[^{}]*:[^{}]*;"#, 1),
        ]),
        Rule(language: .yaml, signals: [
            signal(#"^[\w][\w-]*:\s+\S"#, 2),
            signal(#"^\s*-\s+\S"#, 1),
            signal(#"^---\s*$"#, 2),
        ]),
        Rule(language: .markdown, signals: [
            signal(#"^#{1,6}\s+\S"#, 2),
            signal(#"\[[^\]]+\]\([^)]+\)"#, 2),
            signal(#"```"#, 2),
            signal(#"^\s*[-*+]\s+\S"#, 1),
            signal(#"^>\s"#, 1),
            signal(#"(\*\*[^*]+\*\*|__[^_]+__)"#, 1),
        ]),
    ]
}
