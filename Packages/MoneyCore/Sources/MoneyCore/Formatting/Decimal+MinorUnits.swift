import Foundation

extension Decimal {
    /// Nilai dalam satuan terkecil (sen), dibulatkan `.plain` ke 2 desimal.
    /// Precondition: nilai bukan NaN dan muat di `Int64` setelah dikali 100 (tidak ada wrap diam-diam).
    public var minorUnits: Int64 {
        precondition(!isNaN, "Decimal.minorUnits: nilai NaN")
        var scaled = self * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        precondition(
            !rounded.isNaN && rounded >= Decimal(Int64.min) && rounded <= Decimal(Int64.max),
            "Decimal.minorUnits: nilai di luar jangkauan Int64"
        )
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    public init(minorUnits: Int64) {
        self = Decimal(minorUnits) / 100
    }
}
