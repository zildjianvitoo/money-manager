import Testing
import Foundation
@testable import MoneyCore

@Test func parserEvaluates() throws {
    #expect(try AmountParser.evaluate("19000") == 19000)
    #expect(try AmountParser.evaluate("19000+4500") == 23500)
    #expect(try AmountParser.evaluate("100000-25000×2") == 50000)
    #expect(try AmountParser.evaluate("10÷3") == Decimal(string: "3.33")!)
    #expect(try AmountParser.evaluate("1,5×2") == 3)
}

@Test(arguments: ["12+", "+5", "1,5,2", "×3", "1++2", "abc"])
func parserRejectsMalformed(_ input: String) {
    #expect(throws: AmountParserError.malformed) { try AmountParser.evaluate(input) }
}

@Test func parserRejectsEmptyAndZeroDivision() {
    #expect(throws: AmountParserError.empty) { try AmountParser.evaluate("") }
    #expect(throws: AmountParserError.divisionByZero) { try AmountParser.evaluate("5÷0") }
}
