import SwiftUI
import UIKit
import XCTest
@testable import Oware

/// Text colours on the app's own backgrounds meet WCAG AA (4.5:1 for body text), as the HIG asks.
/// (The audit's contrast check is left out of the UI tests because it measures against photos and
/// wood grain; this checks the colours themselves.)
final class ThemeContrastTests: XCTestCase {
    private func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// Contrast of `text` (with its opacity blended over `background`) against `background`.
    private func contrast(_ text: Color, on background: Color) -> Double {
        let t = rgba(text), bg = rgba(background)
        let blended = (r: t.r * t.a + bg.r * (1 - t.a), g: t.g * t.a + bg.g * (1 - t.a), b: t.b * t.a + bg.b * (1 - t.a))
        let l1 = luminance(blended), l2 = luminance((bg.r, bg.g, bg.b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testTextColoursMeetAAOnEveryBackground() {
        let texts: [(String, Color)] = [("ivory", Theme.ivory), ("ivoryDim", Theme.ivoryDim), ("gold", Theme.gold)]
        let backgrounds: [(String, Color)] = [("night", Theme.night), ("ember", Theme.ember), ("emberLight", Theme.emberLight)]
        for (tName, text) in texts {
            for (bName, background) in backgrounds {
                let ratio = contrast(text, on: background)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tName) on \(bName) is \(String(format: "%.1f", ratio)):1")
            }
        }
    }
}
