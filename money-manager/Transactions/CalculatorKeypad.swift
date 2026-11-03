import SwiftUI

/// Money Manager style calculator keypad. Edits `expression` in place;
/// `=` and `Ya` are handed back to the form, which owns evaluation.
struct CalculatorKeypad: View {
    @Binding var expression: String
    let onEquals: () -> Void
    let onConfirm: () -> Void

    /// Keeps expressions well inside what `AmountParser` accepts.
    private static let maxLength = 40

    private enum Key: Hashable {
        case digit(Character), op(Character), comma, equals, backspace, confirm
    }

    private let rows: [[Key]] = [
        [.op("+"), .op("-"), .op("×"), .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .equals],
        [.digit("4"), .digit("5"), .digit("6"), .comma],
        [.digit("1"), .digit("2"), .digit("3"), .backspace],
    ]

    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
            GridRow {
                keyButton(.digit("0")).gridCellColumns(2)
                keyButton(.confirm).gridCellColumns(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func keyButton(_ key: Key) -> some View {
        Button { press(key) } label: {
            label(for: key)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeypadButtonStyle(isConfirm: key == .confirm))
        .accessibilityLabel(accessibilityName(for: key))
        .buttonRepeatBehavior(key == .backspace ? .enabled : .disabled)
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .digit(let c): Text(String(c)).font(.title2).monospacedDigit()
        case .op(let c): Text(String(c)).font(.title2.weight(.medium))
        case .comma: Text(",").font(.title2)
        case .equals: Text("=").font(.title2.weight(.medium))
        case .backspace: Image(systemName: "delete.left").font(.title3)
        case .confirm: Text("Ya").font(.title3.weight(.semibold))
        }
    }

    private func accessibilityName(for key: Key) -> String {
        switch key {
        case .digit(let c): String(c)
        case .op("+"): "tambah"
        case .op("-"): "kurang"
        case .op("×"): "kali"
        case .op(_): "bagi"
        case .comma: "koma"
        case .equals: "sama dengan"
        case .backspace: "hapus"
        case .confirm: "Ya"
        }
    }

    private func press(_ key: Key) {
        switch key {
        case .digit(let c): append(c)
        case .op(let c):
            // Typing an operator right after another one replaces it.
            if let last = expression.last, "+-×÷".contains(last) { expression.removeLast() }
            append(c)
        case .comma: append(",")
        case .backspace: if !expression.isEmpty { expression.removeLast() }
        case .equals: onEquals()
        case .confirm: onConfirm()
        }
    }

    private func append(_ c: Character) {
        guard expression.count < Self.maxLength else { return }
        expression.append(c)
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    let isConfirm: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isConfirm ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                isConfirm ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
