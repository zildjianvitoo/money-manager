import Testing
import Foundation
@testable import MoneyCore

@Test func formatsRupiah() {
    #expect(MoneyFormatter.string(1_280_402) == "Rp 1.280.402")
    #expect(MoneyFormatter.string(Decimal(string: "1280.5")!) == "Rp 1.280,50")
    #expect(MoneyFormatter.string(-6_807_247) == "-Rp 6.807.247")
    #expect(MoneyFormatter.string(0) == "Rp 0")
}

@Test func formatsEdgeCases() {
    #expect(MoneyFormatter.string(Decimal(string: "1280.05")!) == "Rp 1.280,05")
    #expect(MoneyFormatter.string(1000) == "Rp 1.000")
    #expect(MoneyFormatter.string(1_000_000) == "Rp 1.000.000")
    #expect(MoneyFormatter.string(Decimal(string: "-1280.5")!) == "-Rp 1.280,50")
}

@Test func minorUnitsRoundTrip() {
    #expect(Decimal(string: "19000.25")!.minorUnits == 1_900_025)
    #expect(Decimal(minorUnits: 1_900_025) == Decimal(string: "19000.25")!)
}
