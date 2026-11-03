import SwiftUI
import MoneyCore

/// Keypad expressions for balances, which unlike transaction amounts may be negative (e.g. a credit card).
/// `AmountParser` rejects a leading `-`, so it is read as `0-…`.
enum BalanceExpression {
    static func evaluate(_ expression: String) -> Result<Decimal, AmountParserError> {
        let normalized = expression.hasPrefix("-") ? "0" + expression : expression
        return Result { () throws(AmountParserError) in try AmountParser.evaluate(normalized) }
    }

    /// `-1280.5` → `"-1280,5"`; zero → empty, or `"0"` when an empty field would read as "nothing entered".
    static func expression(for amount: Decimal, keepingZero: Bool = false) -> String {
        if amount == 0 { return keepingZero ? "0" : "" }
        return "\(amount)".replacingOccurrences(of: ".", with: ",")
    }

    /// Errors show once the expression looks complete (or after `=`/`Ya`), not mid-typing like `12+`.
    static func errorMessage(expression: String, result: Result<Decimal, AmountParserError>, forced: Bool) -> String? {
        guard !expression.isEmpty, case .failure(let error) = result else { return nil }
        let looksComplete = expression.last.map { !"+-×÷,".contains($0) } ?? false
        guard forced || looksComplete else { return nil }
        switch error {
        case .divisionByZero: return "Tidak bisa dibagi nol"
        case .tooLarge: return "Nominal terlalu besar"
        case .empty, .malformed: return "Format tidak valid"
        }
    }
}

/// Form row showing a keypad-driven balance; tapping it hands the keypad to this row.
struct BalanceAmountRow: View {
    let title: String
    let expression: String
    let result: Result<Decimal, AmountParserError>
    let isActive: Bool
    let showsError: Bool
    let onTap: () -> Void

    var body: some View {
        let error = BalanceExpression.errorMessage(expression: expression, result: result, forced: showsError)
        Button(action: onTap) {
            VStack(alignment: .trailing, spacing: 4) {
                LabeledContent(title) {
                    Text(displayText)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(expression.isEmpty ? .tertiary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : nil)
        .accessibilityValue(error ?? "")
    }

    /// Raw expression while typing; the formatted amount otherwise.
    private var displayText: String {
        if expression.isEmpty { return "Rp 0" }
        if !isActive, case .success(let value) = result { return MoneyFormatter.string(value) }
        return expression
    }
}
