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

@Test func parserRejectsTooLarge() throws {
    #expect(throws: AmountParserError.tooLarge) { try AmountParser.evaluate("999999999999×999999999") }
    #expect(throws: AmountParserError.tooLarge) { try AmountParser.evaluate("1000000000000000") }
    #expect(throws: AmountParserError.tooLarge) { try AmountParser.evaluate(String(repeating: "9", count: 60)) }
    #expect(try AmountParser.evaluate("999999999999999") == 999_999_999_999_999)
}

@Test func parserPinsEdgeBehaviour() throws {
    #expect(try AmountParser.evaluate("5,") == 5)
    #expect(try AmountParser.evaluate(",5") == Decimal(string: "0.5")!)
    #expect(throws: AmountParserError.malformed) { try AmountParser.evaluate("-5") }
    #expect(try AmountParser.evaluate("100÷10÷2") == 5)
    #expect(try AmountParser.evaluate("2×3÷4") == Decimal(string: "1.5")!)
    #expect(throws: AmountParserError.divisionByZero) { try AmountParser.evaluate("1+5÷0") }
}
