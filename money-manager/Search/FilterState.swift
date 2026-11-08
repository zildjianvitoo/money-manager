import SwiftUI
import MoneyCore

/// The filter shared by the Transaksi and Statistik tabs. Reset when the active profile changes,
/// because its category and asset ids belong to one profile.
@Observable
final class FilterState {
    var filter = TransactionFilter()
}

/// Slider icon with a badge showing how many filter groups are active.
struct FilterToolbarButton: View {
    let activeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .overlay(alignment: .topTrailing) {
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Color.red, in: Circle())
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .accessibilityLabel(activeCount > 0 ? "Filter, \(activeCount) aktif" : "Filter")
    }
}
