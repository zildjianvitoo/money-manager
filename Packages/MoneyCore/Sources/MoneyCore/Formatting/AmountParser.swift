import Foundation

public enum AmountParserError: Error, Equatable {
    case empty
    case malformed
    case divisionByZero
    case tooLarge
}

/// Mengevaluasi ekspresi keypad (`+ - × ÷`, koma desimal). `× ÷` didahulukan, kiri ke kanan.
/// Hasil dibulatkan ke 2 desimal.
public enum AmountParser {
    /// Batas nilai mutlak hasil (999.999.999.999.999) agar aman disimpan sebagai sen di `Int64`.
    public static let maximumAmount: Decimal = 999_999_999_999_999

    private enum Token {
        case number(Decimal)
        case op(Character)
    }

    public static func evaluate(_ expression: String) throws(AmountParserError) -> Decimal {
        guard !expression.isEmpty else { throw .empty }
        let tokens = try tokenize(expression)

        // Tahap 1: kali/bagi. Hasilnya berupa daftar suku yang dijumlahkan.
        guard case .number(let first)? = tokens.first else { throw .malformed }
        var terms: [(sign: Decimal, value: Decimal)] = []
        var sign: Decimal = 1
        var current = first
        var index = 1
        while index < tokens.count {
            guard case .op(let symbol) = tokens[index],
                  index + 1 < tokens.count,
                  case .number(let rhs) = tokens[index + 1]
            else { throw .malformed }
            switch symbol {
            case "×":
                current *= rhs
            case "÷":
                guard rhs != 0 else { throw .divisionByZero }
                current /= rhs
            default:
                terms.append((sign, current))
                sign = symbol == "-" ? -1 : 1
                current = rhs
            }
            index += 2
        }
        terms.append((sign, current))

        // Tahap 2: tambah/kurang.
        var total: Decimal = 0
        for term in terms { total += term.sign * term.value }
        guard !total.isNaN else { throw .tooLarge }

        var source = total
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        guard !rounded.isNaN, abs(rounded) <= maximumAmount else { throw .tooLarge }
        return rounded
    }

    private static func tokenize(_ expression: String) throws(AmountParserError) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var sawComma = false

        func flush() throws(AmountParserError) {
            guard !buffer.isEmpty else { return }
            guard buffer.contains(where: \.isASCIIDigit) else { throw .malformed }
            // Sintaksis sudah valid di sini, jadi gagal/NaN berarti angkanya terlalu besar.
            guard let value = Decimal(string: buffer.replacing(",", with: ".")), !value.isNaN
            else { throw .tooLarge }
            tokens.append(.number(value))
            buffer = ""
            sawComma = false
        }

        for character in expression {
            if character.isASCIIDigit {
                buffer.append(character)
            } else if character == "," {
                guard !sawComma else { throw .malformed }
                sawComma = true
                buffer.append(character)
            } else if "+-×÷".contains(character) {
                try flush()
                tokens.append(.op(character))
            } else {
                throw .malformed
            }
        }
        try flush()
        return tokens
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
