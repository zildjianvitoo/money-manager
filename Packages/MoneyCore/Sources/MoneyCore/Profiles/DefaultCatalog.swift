/// Kategori bawaan untuk setiap profil baru (PRD F6). Urutan array = `sortOrder`.
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
}
