//
//  LanguageDetectorTests.swift
//  BoopTests
//
//  Verifies the content-based language detector classifies representative
//  snippets correctly — including short ones that lack imports/boilerplate —
//  and stays on plain text when it isn't confident.
//

import XCTest
import CodeEditLanguages
@testable import Boop

final class LanguageDetectorTests: XCTestCase {

    /// Assert that `source` is detected as `expected`.
    private func assertDetects(_ source: String,
                               _ expected: CodeLanguage,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        let detected = LanguageDetector.detect(from: source)
        XCTAssertEqual(detected.id, expected.id,
                       "expected \(expected.id.rawValue) but got \(detected.id.rawValue)",
                       file: file, line: line)
    }

    // MARK: - Short snippets (the cases the old AND-chain detector missed)

    func testMinimalPython() {
        assertDetects("def main():\n    print('hello')", .python)
    }

    func testMinimalJavaScript() {
        assertDetects("const x = 1\nconsole.log(x)", .javascript)
    }

    func testMinimalRuby() {
        assertDetects("puts 'hello'\n3.times do |i|\n  puts i\nend", .ruby)
    }

    func testMinimalSwift() {
        assertDetects("func greet() {\n  let name = 1\n  guard let y = x else {}\n}", .swift)
    }

    // MARK: - Structural short-circuits

    func testShebangBash() {
        assertDetects("#!/bin/bash\necho hi", .bash)
    }

    func testPHPTag() {
        assertDetects("<?php echo 'hi'; ?>", .php)
    }

    func testJSON() {
        assertDetects("{\n  \"name\": \"Boop\",\n  \"version\": 1\n}", .json)
    }

    func testHTMLDoctype() {
        assertDetects("<!DOCTYPE html>\n<html><body>Hi</body></html>", .html)
    }

    // MARK: - Scored matches across languages

    func testGo() {
        assertDetects("package main\nfunc main() { fmt.Println(\"hi\") }", .go)
    }

    func testRust() {
        assertDetects("fn main() {\n    println!(\"hi\");\n}", .rust)
    }

    func testTypeScript() {
        assertDetects("interface User { name: string; age: number }", .typescript)
    }

    func testC() {
        assertDetects("#include <stdio.h>\nint main() { printf(\"hi\"); }", .c)
    }

    func testCPlusPlus() {
        assertDetects("#include <iostream>\nint main(){ std::cout << 1; }", .cpp)
    }

    func testJava() {
        assertDetects("public class Main { public static void main(String[] a){ System.out.println(1);}}",
                      .java)
    }

    func testSQL() {
        assertDetects("SELECT id, name FROM users WHERE id = 1", .sql)
    }

    func testCSS() {
        assertDetects(".btn { color: #fff; padding: 4px; }", .css)
    }

    func testMarkdown() {
        assertDetects("# Title\n\nSome **bold** and a [link](http://x)", .markdown)
    }

    func testYAML() {
        assertDetects("name: build\non: push\njobs:\n  - run: echo", .yaml)
    }

    // MARK: - Negative case

    func testPlainProseStaysDefault() {
        assertDetects("just some plain english prose here", .default)
    }

    func testEmptyStaysDefault() {
        assertDetects("   \n\t\n", .default)
    }
}
