import Foundation

public struct NetWorth: Equatable {
    public let assets: Decimal
    /// Jumlah saldo negatif; bernilai negatif.
    public let liabilities: Decimal
    public var total: Decimal { assets + liabilities }

    public init(assets: Decimal, liabilities: Decimal) {
        self.assets = assets
        self.liabilities = liabilities
    }
}

/// Menghitung saldo aset dari saldo awal dan transaksi. Hanya transaksi yang `asset`-nya atau `toAsset`-nya
/// aset itu (dibandingkan lewat `id`) yang dihitung; sisanya diabaikan.
public enum BalanceCalculator {
    public static func balance(of asset: AssetAccount, transactions: [MoneyTransaction]) -> Decimal {
        transactions.reduce(asset.initialBalance) { $0 + delta(of: $1, for: asset) }
    }

    /// Hanya aset dengan `includeInTotal`, diarsipkan atau tidak (uangnya tetap ada).
    /// Saldo positif masuk `assets`, negatif masuk `liabilities`, nol diabaikan.
    public static func netWorth(assets: [AssetAccount], transactions: [MoneyTransaction]) -> NetWorth {
        var positive: Decimal = 0
        var negative: Decimal = 0
        for asset in assets where asset.includeInTotal {
            let b = balance(of: asset, transactions: transactions)
            if b > 0 { positive += b } else if b < 0 { negative += b }
        }
        return NetWorth(assets: positive, liabilities: negative)
    }

    /// Saldo setelah tiap transaksi aset ini, urut tanggal naik lalu `createdAt` naik.
    public static func runningBalances(
        of asset: AssetAccount, transactions: [MoneyTransaction]
    ) -> [(transaction: MoneyTransaction, balanceAfter: Decimal)] {
        let own = transactions
            .filter { touches($0, asset) }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        var running = asset.initialBalance
        return own.map { tx in
            running += delta(of: tx, for: asset)
            return (transaction: tx, balanceAfter: running)
        }
    }

    // MARK: - Private

    private static func touches(_ tx: MoneyTransaction, _ asset: AssetAccount) -> Bool {
        tx.asset?.id == asset.id || tx.toAsset?.id == asset.id
    }

    /// Pengaruh satu transaksi terhadap saldo `asset` (0 bila tidak menyentuhnya).
    private static func delta(of tx: MoneyTransaction, for asset: AssetAccount) -> Decimal {
        let isSource = tx.asset?.id == asset.id
        let isTarget = tx.toAsset?.id == asset.id
        var result: Decimal = 0
        switch tx.type {
        case .income: if isSource { result += tx.amount }
        case .expense: if isSource { result -= tx.amount }
        case .transfer:
            if isSource { result -= tx.amount + tx.fee }
            if isTarget { result += tx.amount }
        case .adjustment: if isSource { result += tx.amount }
        }
        return result
    }
}
