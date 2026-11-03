import Foundation
import SwiftData

public enum TransactionQueries {
    /// Interval bulan yang memuat `date`: [awal bulan, awal bulan berikutnya). Akhir bersifat eksklusif.
    public static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// Interval tahun yang memuat `date`: [1 Jan, 1 Jan tahun berikutnya). Akhir bersifat eksklusif.
    public static func yearInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .year, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// Transaksi satu profil dalam interval (`start <= date < end`), terbaru di atas.
    public static func descriptor(profileID: UUID, interval: DateInterval) -> FetchDescriptor<MoneyTransaction> {
        let start = interval.start
        let end = interval.end
        return FetchDescriptor<MoneyTransaction>(
            predicate: #Predicate { $0.profileID == profileID && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
    }
}
