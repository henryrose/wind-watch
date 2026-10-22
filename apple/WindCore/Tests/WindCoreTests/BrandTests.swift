import Testing
@testable import WindCore

@Suite("Brand")
struct BrandTests {
    @Test func tierThresholds() {
        #expect(BrandMark.Tier(points: 1024) == .full)
        #expect(BrandMark.Tier(points: 48) == .full)
        #expect(BrandMark.Tier(points: 47) == .small)
        #expect(BrandMark.Tier(points: 24) == .small)
        #expect(BrandMark.Tier(points: 23) == .tiny)
        #expect(BrandMark.Tier(points: 17) == .tiny)
    }

    @Test func streakCountFollowsTier() {
        #expect(BrandMark.glyph(.full).streaks.count == 3)
        #expect(BrandMark.glyph(.small).streaks.count == 2)
        #expect(BrandMark.glyph(.tiny).streaks.count == 1)
    }
}
