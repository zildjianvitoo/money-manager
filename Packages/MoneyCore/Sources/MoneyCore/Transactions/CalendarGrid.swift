import Foundation

public enum CalendarGrid {
    /// Baris minggu untuk bulan yang memuat `month`. Setiap baris berisi 7 sel; sel di luar bulan bernilai nil.
    public static func weeks(for month: Date, calendar: Calendar) -> [[Date?]] {
        let interval = TransactionQueries.monthInterval(containing: month, calendar: calendar)
        let first = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Simbol hari pendek sesuai `firstWeekday` kalender, mis. ["Min", "Sen", ...].
    public static func weekdaySymbols(calendar: Calendar) -> [String] {
        // Selalu bahasa Indonesia, apa pun bahasa perangkat; urutan tetap mengikuti `firstWeekday`.
        let start = calendar.firstWeekday - 1
        var indonesian = calendar
        indonesian.locale = Locale(identifier: "id_ID")
        let symbols = indonesian.shortWeekdaySymbols
        return Array(symbols[start...] + symbols[..<start])
    }
}
