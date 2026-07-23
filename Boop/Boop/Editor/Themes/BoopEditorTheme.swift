//
//  BoopEditorTheme.swift
//  Boop
//

import Cocoa
import CodeEditSourceEditor

enum BoopEditorTheme {

    static func theme(for appearance: NSAppearance) -> EditorTheme {
        let body = ColorPair.body.value(for: appearance).rgb
        let selectionColor = NSColor(red: 0.19, green: 0.44, blue: 0.71, alpha: 1).rgb
        let lineHighlightColor = ColorPair.normal.value(for: appearance).withAlphaComponent(0.2).rgb
        let invisiblesColor = Colors.commentGreyDarkest.withAlphaComponent(0.5).rgb

        return EditorTheme(
            text: .init(color: body),
            insertionPoint: body,
            invisibles: .init(color: invisiblesColor),
            background: ColorPair.background.value(for: appearance).rgb,
            lineHighlight: lineHighlightColor,
            selection: selectionColor,
            keywords: .init(color: ColorPair.green.value(for: appearance).rgb),
            commands: .init(color: ColorPair.green.value(for: appearance).rgb),
            types: .init(color: ColorPair.cyanish.value(for: appearance).rgb),
            attributes: .init(color: ColorPair.cyanish.value(for: appearance).rgb),
            variables: .init(color: body),
            values: .init(color: ColorPair.orangish.value(for: appearance).rgb),
            numbers: .init(color: ColorPair.orangish.value(for: appearance).rgb),
            strings: .init(color: ColorPair.red.value(for: appearance).rgb),
            characters: .init(color: ColorPair.red.value(for: appearance).rgb),
            comments: .init(color: ColorPair.comments.value(for: appearance).rgb)
        )
    }
}

private extension NSColor {
    /// CodeEditSourceEditor reads HSB/RGB components of theme colors internally, which
    /// traps on grayscale colorspaces (e.g. `NSColor(white:alpha:)`). Convert to sRGB so
    /// component access is always valid.
    var rgb: NSColor {
        usingColorSpace(.sRGB) ?? self
    }
}
