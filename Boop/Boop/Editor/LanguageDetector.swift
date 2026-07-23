//
//  LanguageDetector.swift
//  Boop
//
//  Cheap, content-based language detection for CodeEditSourceEditor.
//  Boop has no filenames to go on, so detection is purely heuristic: it looks
//  only at a bounded prefix of the document (plus the first non-empty line)
//  and returns a specific CodeLanguage when reasonably confident, or
//  `.default` when it isn't. This is called from the facade's onTextChange
//  (debounced) — keep it allocation-light and fast.
//

import Foundation
import CodeEditLanguages

enum LanguageDetector {

    /// Bound how much of the document we inspect. Detection only ever needs
    /// a small prefix, so this keeps the scan cheap even for huge documents.
    private static let prefixLength = 2048

    static func detect(from text: String) -> CodeLanguage {
        // Bounded prefix to scan for keywords/markers.
        let prefix = String(text.prefix(prefixLength))
        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .default
        }

        let firstLine = firstNonEmptyLine(in: prefix)

        // MARK: - Shebang
        if firstLine.hasPrefix("#!") {
            if firstLine.contains("bash") || firstLine.contains("/sh") || firstLine.contains("zsh") {
                return .bash
            }
            if firstLine.contains("python") {
                return .python
            }
            if firstLine.contains("node") {
                return .javascript
            }
            if firstLine.contains("ruby") {
                return .ruby
            }
        }

        // MARK: - Unambiguous leading markers
        if prefix.hasPrefix("<?php") {
            return .php
        }
        if prefix.hasPrefix("<!DOCTYPE html") || prefix.hasPrefix("<!doctype html")
            || prefix.hasPrefix("<html") {
            return .html
        }
        if prefix.hasPrefix("<?xml") {
            // No dedicated XML language is registered; HTML's markup grammar
            // is the closest available fit.
            return .html
        }

        // MARK: - JSON
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrefix.hasPrefix("{") || trimmedPrefix.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])) != nil {
                return .json
            }
        }

        // MARK: - YAML
        if prefix.hasPrefix("---\n") || prefix.hasPrefix("---\r\n") {
            return .yaml
        }
        if looksLikeYAMLKeyLine(firstLine) {
            return .yaml
        }

        // MARK: - Markdown
        if firstLine.hasPrefix("# ") || firstLine.hasPrefix("## ") || firstLine.hasPrefix("### ")
            || prefix.contains("](") {
            return .markdown
        }

        // MARK: - Keyword scans (order matters: most specific first)
        if prefix.contains("func ") && (prefix.contains("import Foundation")
            || (prefix.contains("let ") && prefix.contains("var "))) {
            return .swift
        }
        if prefix.contains("def ") && prefix.contains("import ") && prefix.contains(":") {
            return .python
        }
        if prefix.contains("function ") || prefix.contains("const ") || prefix.contains("=>") {
            return .javascript
        }
        if prefix.contains("package main") || prefix.contains("func (") {
            return .go
        }
        if prefix.contains("fn ") || prefix.contains("let mut") {
            return .rust
        }
        if prefix.contains("public class") || prefix.contains("System.out") {
            return .java
        }
        if prefix.contains("SELECT ") || prefix.contains("INSERT ") {
            return .sql
        }

        // Nothing matched confidently.
        return .default
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

    /// Matches a plain `key: value` or `key:` line, the shape of a YAML
    /// document that lacks `---` front-matter delimiters.
    private static func looksLikeYAMLKeyLine(_ line: String) -> Bool {
        guard let colonIndex = line.firstIndex(of: ":") else { return false }
        let key = line[line.startIndex..<colonIndex]
        guard !key.isEmpty else { return false }
        // Keys should look like identifiers (letters, digits, -, _), not code.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
