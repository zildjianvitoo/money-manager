/// Kategori bawaan profil baru (PRD F6). Urutan array = `sortOrder`. `expense`/`income` untuk profil pribadi.
public enum DefaultCatalog {
    public static let expense: [(emoji: String, name: String)] = [
        ("🍜", "Makanan"),
        ("🚕", "Transportasi"),
        ("🏠", "Biaya Sewa Tempat Tinggal"),
        ("🪑", "Kebutuhan Rumah"),
        ("👫", "Kehidupan Sosial"),
        ("🧥", "Pakaian"),
        ("💄", "Kecantikan"),
        ("💊", "Kesehatan"),
        ("📙", "Pendidikan"),
        ("🎬", "Hiburan"),
        ("📈", "Invest"),
        ("📦", "Lainnya"),
    ]

    public static let income: [(emoji: String, name: String)] = [
        ("💰", "Gaji"),
        ("🎁", "Bonus"),
        ("🏪", "Usaha"),
        ("📈", "Hasil Investasi"),
        ("📦", "Lainnya"),
    ]

    public static let businessExpense: [(emoji: String, name: String)] = [
        ("📥", "Modal/Stok"),
        ("🧾", "Tagihan & Langganan"),
        ("👥", "Gaji Tim"),
        ("⚙️", "Operasional"),
        ("🚕", "Transportasi"),
        ("📣", "Iklan & Promosi"),
        ("🏛️", "Pajak & Biaya Admin"),
        ("📦", "Lainnya"),
    ]

    public static let businessIncome: [(emoji: String, name: String)] = [
        ("🛒", "Penjualan"),
        ("🤝", "Jasa/Komisi"),
        ("📦", "Lainnya"),
    ]

    public static func expense(for kind: ProfileKind) -> [(emoji: String, name: String)] {
        kind == .business ? businessExpense : expense
    }

    public static func income(for kind: ProfileKind) -> [(emoji: String, name: String)] {
        kind == .business ? businessIncome : income
    }
}
