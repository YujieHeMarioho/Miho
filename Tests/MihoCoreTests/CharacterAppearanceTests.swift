import XCTest
@testable import MihoCore

final class CharacterAppearanceTests: XCTestCase {
    func testDefaultBodyIsSphereInAllThreeDimensions() {
        let appearance = CharacterAppearance()
        let r = appearance.shape.radii
        XCTAssertEqual(r.0,r.1); XCTAssertEqual(r.1,r.2)
        XCTAssertEqual(appearance.glasses,.sunglasses)
        XCTAssertEqual(appearance.accessory,.headphones)
    }
    func testPersonalChoicesSurviveCodingAndCorruptPreferencesRecover() throws {
        var appearance = CharacterAppearance()
        appearance.name = "Huno"; appearance.shape = .squircle; appearance.ears = .cat
        appearance.eyes = .wink; appearance.glasses = .round; appearance.accessory = .crown
        appearance.bodyColor = 0xEFE1D2; appearance.accessoryColor = 0xFFD399
        appearance.glassesColor = 0x8000E1; appearance.surface = .satin
        XCTAssertEqual(CharacterAppearance.load(try JSONEncoder().encode(appearance)),appearance)
        XCTAssertEqual(CharacterAppearance.load(Data("invalid".utf8)),CharacterAppearance())
        XCTAssertEqual(CharacterAppearance.load(nil),CharacterAppearance())
    }
    func testDisplayNameHasFallbackAndLengthLimit() {
        var appearance = CharacterAppearance(); appearance.name = "  \n  "
        XCTAssertEqual(appearance.displayName,"咪虎")
        appearance.name = String(repeating: "虎",count: 30)
        XCTAssertEqual(appearance.displayName.count,24)
    }
}
