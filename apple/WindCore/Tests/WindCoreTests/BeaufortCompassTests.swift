import Foundation
import SwiftUI
import Testing
@testable import WindCore

@Suite("Beaufort")
struct BeaufortTests {
    @Test func bandsMatchHandoff() {
        #expect(Beaufort.step(kn: 0) == 0)
        #expect(Beaufort.step(kn: 1) == 1)
        #expect(Beaufort.step(kn: 3) == 1)
        #expect(Beaufort.step(kn: 4) == 2)
        #expect(Beaufort.step(kn: 6) == 2)
        #expect(Beaufort.step(kn: 7) == 3)
        #expect(Beaufort.step(kn: 10) == 3)
        #expect(Beaufort.step(kn: 11) == 4)
        #expect(Beaufort.step(kn: 16) == 4)
        #expect(Beaufort.step(kn: 17) == 5)
        #expect(Beaufort.step(kn: 21) == 5)
        #expect(Beaufort.step(kn: 22) == 6)
        #expect(Beaufort.step(kn: 27) == 6)
        #expect(Beaufort.step(kn: 28) == 7)
        #expect(Beaufort.step(kn: 33) == 7)
        #expect(Beaufort.step(kn: 34) == 8)
        #expect(Beaufort.step(kn: 40) == 8)
        #expect(Beaufort.step(kn: 41) == 9)
        #expect(Beaufort.step(kn: 47) == 9)
        #expect(Beaufort.step(kn: 48) == 10)
        #expect(Beaufort.step(kn: 55) == 10)
        #expect(Beaufort.step(kn: 56) == 11)
        #expect(Beaufort.step(kn: 64) == 12)
        #expect(Beaufort.step(kn: 120) == 12)
        #expect(Beaufort.step(kn: -5) == 0)
    }

    @Test func sharedTokens() {
        #expect(Beaufort.colorToken(step: 0).assetName == "bft.calm")
        #expect(Beaufort.colorToken(step: 1).assetName == "bft.calm")
        #expect(Beaufort.colorToken(step: 2).assetName == "bft.2")
        #expect(Beaufort.colorToken(step: 9).assetName == "bft.9")
        #expect(Beaufort.colorToken(step: 10).assetName == "bft.10")
        #expect(Beaufort.colorToken(step: 11).assetName == "bft.10")
        #expect(Beaufort.colorToken(step: 12).assetName == "bft.10")
        #expect(Beaufort.colorToken(step: 10).strokeAssetName == "bft.8")
        #expect(Beaufort.colorToken(step: 4).strokeAssetName == nil)
    }

    @Test func hexesMatchHandoff41() {
        let expected: [(String, String, String)] = [
            ("bft.calm", "#5C6B7A", "#8A97A6"), ("bft.2", "#4FA3D8", "#2A86C4"),
            ("bft.3", "#3FC2A0", "#1E9E80"), ("bft.4", "#8DD44A", "#5FA82E"),
            ("bft.5", "#F2D13D", "#C9A800"), ("bft.6", "#F59A2B", "#E07F12"),
            ("bft.7", "#EC5A2A", "#D6451A"), ("bft.8", "#E0245E", "#C7154B"),
            ("bft.9", "#A32CD1", "#8C1FB3"), ("bft.10", "#F5F5F7", "#1B1B1F"),
        ]
        #expect(Beaufort.tokens.count == expected.count)
        for (token, e) in zip(Beaufort.tokens, expected) {
            #expect(token.assetName == e.0)
            #expect(token.darkHex == e.1)
            #expect(token.lightHex == e.2)
        }
    }

    @Test func rangeText() {
        #expect(Beaufort.rangeText(step: 0) == "≤ 3")
        #expect(Beaufort.rangeText(step: 1) == "≤ 3")
        #expect(Beaufort.rangeText(step: 4) == "11–16")
        #expect(Beaufort.rangeText(step: 12) == "48+")
    }

    @Test func hexColorParses() {
        let c = Color(hex: "#8DD44A").resolve(in: EnvironmentValues())
        #expect(abs(Double(c.red) - 0x8D / 255.0) < 0.01)
        #expect(abs(Double(c.green) - 0xD4 / 255.0) < 0.01)
        #expect(abs(Double(c.blue) - 0x4A / 255.0) < 0.01)
        #expect(c.opacity == 1)
        let noHash = Color(hex: "FFB340").resolve(in: EnvironmentValues())
        #expect(abs(Double(noHash.red) - 1) < 0.01)
        #expect(Beaufort.colorToken(step: 4).color(for: .dark) == Color(hex: "#8DD44A"))
        #expect(Beaufort.colorToken(step: 4).color(for: .light) == Color(hex: "#5FA82E"))
        #expect(Beaufort.colorToken(step: 10).strokeColor(for: .dark) == Color(hex: "#E0245E"))
    }
}

@Suite("Compass")
struct CompassTests {
    @Test(arguments: [
        (0, "N"), (22, "N"), (23, "NE"), (45, "NE"), (67, "NE"), (68, "E"), (90, "E"), (112, "E"),
        (113, "SE"), (135, "SE"), (157, "SE"), (158, "S"), (180, "S"), (202, "S"),
        (203, "SW"), (225, "SW"), (247, "SW"), (248, "W"), (270, "W"), (292, "W"),
        (293, "NW"), (315, "NW"), (337, "NW"),
    ])
    func sectors(dirFrom: Int, label: String) {
        #expect(Compass.label(from: dirFrom) == label)
        #expect(Compass.fromText(dirFrom: dirFrom) == "from \(label)")
    }

    @Test func wrapAtNorth() {
        #expect(Compass.label(from: 338) == "N")
        #expect(Compass.label(from: 350) == "N")
        #expect(Compass.label(from: 359) == "N")
        #expect(Compass.label(from: 360) == "N")
        #expect(Compass.label(from: 361) == "N")
        #expect(Compass.label(from: -10) == "N")
        #expect(Compass.label(from: 720 + 290) == "W")
    }

    @Test func rotationIsFromPlus180() {
        #expect(Compass.arrowRotation(dirFrom: 290) == 110)
        #expect(Compass.arrowRotation(dirFrom: 283) == 103)
        #expect(Compass.arrowRotation(dirFrom: 0) == 180)
        #expect(Compass.arrowRotation(dirFrom: 180) == 0)
        #expect(Compass.arrowRotation(dirFrom: 359) == 179)
        #expect(Compass.toBearing(dirFrom: 290) == 110)
    }

    @Test func inlineSymbolUsesToBearing() {
        #expect(Compass.arrowSymbolName(dirFrom: 180) == "arrow.up")        // from S → blows N
        #expect(Compass.arrowSymbolName(dirFrom: 225) == "arrow.up.right")  // from SW → NE
        #expect(Compass.arrowSymbolName(dirFrom: 270) == "arrow.right")     // from W → E
        #expect(Compass.arrowSymbolName(dirFrom: 315) == "arrow.down.right")
        #expect(Compass.arrowSymbolName(dirFrom: 0) == "arrow.down")
        #expect(Compass.arrowSymbolName(dirFrom: 45) == "arrow.down.left")
        #expect(Compass.arrowSymbolName(dirFrom: 90) == "arrow.left")
        #expect(Compass.arrowSymbolName(dirFrom: 135) == "arrow.up.left")
        #expect(Compass.arrowSymbolName(dirFrom: 290) == "arrow.right")     // ref hour 0
    }

    @Test func spoken() {
        #expect(Compass.spokenFromText(dirFrom: 290) == "from the west")
        #expect(Compass.spokenFromText(dirFrom: 45) == "from the northeast")
    }
}
