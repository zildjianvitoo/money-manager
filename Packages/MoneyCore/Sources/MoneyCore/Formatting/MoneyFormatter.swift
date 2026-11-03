import Foundation

/// Memformat nominal rupiah gaya `id_ID`: `Rp 1.280.402`, `Rp 1.280,50`, `-Rp 6.807.247`.
/// Pengelompokan dibangun manual agar hasilnya deterministik (tanpa spasi non-breaking).
public enum MoneyFormatter {
    public static func string(_ amount: Decimal) -> String {
        let units = amount.minorUnits
        let magnitude = units.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100

        var digits = String(whole)
        var grouped = ""
        while digits.count > 3 {
            grouped = "." + digits.suffix(3) + grouped
            digits = String(digits.dropLast(3))
        }
        grouped = digits + grouped

        let sign = units < 0 ? "-" : ""
        let decimals = fraction == 0 ? "" : "," + (fraction < 10 ? "0" : "") + String(fraction)
        return "\(sign)Rp \(grouped)\(decimals)"
    }
}
