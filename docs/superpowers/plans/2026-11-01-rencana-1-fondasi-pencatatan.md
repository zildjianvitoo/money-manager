# Rencana 1 — Fondasi, Pencatatan Inti, Aset & Kategori

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aplikasi iPhone (iOS 26+, Liquid Glass, sesuai HIG) yang sudah bisa dipakai mencatat harian: multi-profil dengan avatar di tab bar native dan gesture tap/double-tap/long-press seperti Instagram, input transaksi dengan keypad kalkulator, daftar Harian per bulan, aset dengan saldo, serta kelola kategori dan profil.

**Architecture:** Semua model SwiftData dan logika tanpa UI ada di Swift package lokal `Packages/MoneyCore`, sehingga bisa dites cepat dengan `swift test` di macOS. Target app `money-manager` hanya berisi view SwiftUI yang memanggil service dari `MoneyCore`. Isolasi profil dijaga dengan field scalar `profileID: UUID` di setiap model dan setiap query.

**Tech Stack:** Swift 6.4, SwiftUI (iOS 26 Liquid Glass), sedikit UIKit untuk gesture tab bar, SwiftData, Observation, Swift Testing, Xcode 27.2.

**Spec:** [`docs/PRD-money-manager.md`](../../PRD-money-manager.md). Rencana ini mencakup F1, F2, F3 (Harian saja), F5, F6, dan bagian model F13 dari PRD.

**Di luar rencana ini (rencana berikutnya):**
- **Rencana 2:** Import & Export xlsx/csv (F10, F11), menunggu file contoh export Money Manager.
- **Rencana 3:** Kalender, Bulanan, Statistik (F3 sisa, F4), Face ID (F12), aktivasi iCloud (F13).
- **Rencana 4:** Anggaran, Berulang/Cicilan, Cari/Filter/Favorit (F7, F8, F9).

## Global Constraints

- Deployment target iOS **26.0**, iPhone saja (`TARGETED_DEVICE_FAMILY = 1`). Package `MoneyCore`: `platforms: [.iOS("26.0"), .macOS("26.0")]`, `swift-tools-version: 6.2`.
- **UI mengikuti PRD bagian 7 "Pedoman UI"**:
  - Komponen sistem iOS 26 (`TabView`, `NavigationStack` large title, `List` inset grouped, sheet + detent, `confirmationDialog`, swipe actions, `ContentUnavailableView`).
  - Efek glass tidak ditiru sendiri; `.glassEffect` / `.buttonStyle(.glassProminent)` hanya untuk tombol + yang mengambang.
  - Warna semantic, dengan `tint` = warna profil aktif. Pendapatan `.blue`, pengeluaran `.red`.
  - Text style sistem; nominal memakai `.monospacedDigit()`.
  - SF Symbols. Target sentuh ≥ 44 pt. Label VoiceOver di setiap tombol ikon.
  - Haptic hanya untuk simpan, ganti profil, dan hapus.
- **Verifikasi setiap task UI** di simulator iOS 26.3, minimal di:
  - iPhone 17 Pro (light dan dark).
  - iPhone 16e (layar kecil).
  - Ukuran teks aksesibilitas terbesar (`xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`).

  Ambil screenshot sebagai bukti. Jangan klaim "sudah dicek" hanya dari membaca kode.
- Nominal **tidak pernah** `Double`. Disimpan sebagai `amountMinor: Int64` (sen, ×100) dan diekspos sebagai `amount: Decimal`.
- Model wajib kompatibel CloudKit sejak awal:
  - Setiap properti punya nilai default atau optional.
  - Setiap relasi optional dan punya inverse.
  - Tidak boleh `@Attribute(.unique)`.
- Setiap model bisnis punya `profileID: UUID`. Setiap query transaksi, aset, dan kategori **wajib** memfilter `profileID`.
- Model transaksi bernama `MoneyTransaction` (bukan `Transaction`, bentrok dengan `SwiftUI.Transaction`) dan model kategori bernama `MoneyCategory` (bukan `Category`, bentrok dengan runtime ObjC).
- Enum disimpan sebagai `String` mentah (`typeRaw`, `groupRaw`, `kindRaw`) agar bisa dipakai di `#Predicate`.
- Format uang: `Rp 1.280.402`. Desimal ditampilkan hanya kalau nilainya bukan bulat (`Rp 1.280,50`). Negatif: `-Rp 6.807.247`. Locale `id_ID`.
- Copy UI dalam bahasa Indonesia, sesuai istilah PRD (Pendapatan, Pengeluaran, Transfer, Aset, Kategori, Catatan, Deskripsi, Simpan, Simpan & Lanjut).
- Profil pertama bernama **"Pribadi"**. Profil baru diisi kategori default PRD F6 dan satu aset **"Tunai"** (grup Tunai).
- Target app memakai `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Service di `MoneyCore` yang memakai `ModelContext` ditandai `@MainActor`.
- Perintah test package: `swift test --package-path Packages/MoneyCore`.
- Perintah build app: `xcodebuild -project money-manager.xcodeproj -scheme money-manager -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3' build`.

## Review Focus

1. **Data bocor antar profil.** Transaksi, aset, atau kategori profil A muncul saat profil B aktif, termasuk di picker form dan saran catatan. Harus tidak pernah terjadi. Dites di Task 4 (`profileIsolation`) dan Task 9 (`suggestionsAreProfileScoped`).
2. **Double-tap saat hanya ada satu profil, profil sebelumnya sudah dihapus, atau jembatan gesture tab bar gagal menemukan `UITabBar`** (mis. setelah update iOS). Seharusnya tidak berbuat apa-apa, tidak crash, dan switcher tetap bisa dibuka dari Lainnya. Dites di Task 3 (`switchToPreviousWithoutPrevious`, `previousClearedWhenDeleted`) dan di Task 10, Step 5 (verifikasi fallback).
3. **Ekspresi keypad yang aneh**, seperti `12+`, `+5`, `5÷0`, `1,5,2`, atau string kosong. Seharusnya error yang jelas, bukan crash atau angka salah. Dites di Task 1 (`parserRejectsMalformed`).
4. **Transaksi lintas batas bulan dan hari** (mis. 31 Okt 23:59 vs 1 Nov 00:00). Harus masuk ke bulan dan hari yang benar menurut kalender lokal. Dites di Task 5 (`monthBoundary`).
5. **Menghapus kategori induk yang punya subkategori dan transaksi.** Semua transaksi (termasuk milik subkategori) pindah ke pengganti, dan tidak ada yang yatim. Dites di Task 8 (`deleteParentMovesSubcategoryTransactions`).

---

## Struktur File

```
Packages/MoneyCore/
├── Package.swift
├── Sources/MoneyCore/
│   ├── Formatting/MoneyFormatter.swift      — Decimal → "Rp 1.280.402"
│   ├── Formatting/AmountParser.swift        — ekspresi keypad → Decimal
│   ├── Models/Profile.swift
│   ├── Models/AssetAccount.swift            — + enum AssetGroup
│   ├── Models/MoneyCategory.swift           — + enum CategoryKind
│   ├── Models/MoneyTransaction.swift             — + enum TransactionType
│   ├── Models/MoneySchema.swift             — daftar model + container factory
│   ├── Profiles/ProfileStore.swift          — profil aktif & sebelumnya (UserDefaults)
│   ├── Profiles/ProfileService.swift        — buat/hapus profil + seeding default
│   ├── Profiles/DefaultCatalog.swift        — data kategori default
│   ├── Transactions/TransactionService.swift — validasi, simpan, ubah, hapus, duplikat
│   ├── Transactions/TransactionQueries.swift — fetch per profil & bulan
│   ├── Transactions/TransactionSummary.swift — ringkasan bulan & grup harian
│   ├── Transactions/NoteSuggester.swift
│   ├── Assets/BalanceCalculator.swift
│   ├── Assets/AssetService.swift
│   └── Categories/CategoryService.swift
└── Tests/MoneyCoreTests/  (satu file test per file sumber, nama <Sumber>Tests.swift)

money-manager/  (target app, folder tersinkron otomatis)
├── money_managerApp.swift                   — modifikasi: container + ProfileStore
├── ContentView.swift                        — dihapus, diganti RootView
├── App/RootView.swift                       — TabView native (Liquid Glass) + state tab
├── App/Color+Hex.swift                      — Color/UIColor dari "#RRGGBB"
├── App/ProfileTabIcon.swift                 — render avatar profil → UIImage untuk ikon tab
├── App/TabBarGestureBridge.swift            — double-tap & long-press pada UITabBar (UIKit)
├── App/ProfileSwitcherSheet.swift
├── App/ToastView.swift
├── Transactions/TransactionListView.swift   — header bulan + ringkasan + Harian
├── Transactions/DailySectionView.swift
├── Transactions/TransactionFormView.swift
├── Transactions/CalculatorKeypad.swift
├── Transactions/PickerSheets.swift          — pemilih kategori & aset
├── Assets/AssetListView.swift
├── Assets/AssetDetailView.swift
├── Assets/AssetFormView.swift
├── More/MoreView.swift                      — halaman Lainnya
├── More/ProfileManagementView.swift
└── More/CategoryManagementView.swift
```

---

### Task 0: Repo git, package MoneyCore, dan tautan ke app

**Files:**
- Create: `.gitignore`, `Packages/MoneyCore/Package.swift`, `Packages/MoneyCore/Sources/MoneyCore/MoneyCore.swift`, `Packages/MoneyCore/Tests/MoneyCoreTests/SmokeTests.swift`
- Modify: `money-manager.xcodeproj` (via Xcode, langkah manual pengguna)

**Interfaces:**
- Produces: library product `MoneyCore`, yang bisa di-`import MoneyCore` dari target app.

- [ ] **Step 1:** `git init`. Buat `.gitignore` berisi `.DS_Store`, `xcuserdata/`, `.build/`, `DerivedData/`, `*.xcuserstate`, `.swiftpm/`.
- [ ] **Step 1b:** Di `money-manager.xcodeproj/project.xcproj`, ubah dua nilai berikut. Edit hanya kedua nilai string itu, jangan mengubah struktur file.
  - `"IPHONEOS_DEPLOYMENT_TARGET": "27.2"` → `"26.0"`
  - `"TARGETED_DEVICE_FAMILY": "1,2"` → `"1"`
- [ ] **Step 2:** Buat `Package.swift` (tools 6.2, platforms sesuai Global Constraints, target `MoneyCore` dan test target `MoneyCoreTests`). Buat `MoneyCore.swift` berisi `public enum MoneyCore { public static let version = "0.1.0" }`.
- [ ] **Step 3:** Tulis test `@Test func smoke() { #expect(MoneyCore.version == "0.1.0") }`.
- [ ] **Step 4:** Jalankan `swift test --package-path Packages/MoneyCore`. Harus PASS (1 test).
- [ ] **Step 5 — [MANUAL PENGGUNA]:** Di Xcode: *File → Add Package Dependencies… → Add Local…* → pilih `Packages/MoneyCore` → tambahkan product `MoneyCore` ke target `money-manager`. Agen menunggu konfirmasi pengguna sebelum lanjut.
- [ ] **Step 6:** Tambahkan `import MoneyCore` di `money_managerApp.swift`, lalu jalankan perintah build app (destination iOS 26.3). Harus `** BUILD SUCCEEDED **`. Ini sekaligus membuktikan deployment target 26.0 berlaku.
- [ ] **Step 7:** Commit semua file, termasuk `docs/`: `chore: init repo dan package MoneyCore`.

### Task 1: MoneyFormatter & AmountParser

**Files:**
- Create: `Sources/MoneyCore/Formatting/MoneyFormatter.swift`, `Sources/MoneyCore/Formatting/AmountParser.swift`
- Test: `Tests/MoneyCoreTests/MoneyFormatterTests.swift`, `Tests/MoneyCoreTests/AmountParserTests.swift`

**Interfaces:**
- Produces:
  - `public enum MoneyFormatter { static func string(_ amount: Decimal) -> String }`
  - `public enum AmountParser { static func evaluate(_ expression: String) throws(AmountParserError) -> Decimal }`
  - `public enum AmountParserError: Error, Equatable { case empty, malformed, divisionByZero }`
  - `extension Decimal { public var minorUnits: Int64; public init(minorUnits: Int64) }` (pembulatan `.plain` ke 2 desimal)

Ekspresi memakai simbol keypad: `+`, `-`, `×`, `÷`, dan `,` sebagai pemisah desimal. Prioritas operator: `× ÷` sebelum `+ -`, kiri ke kanan. Hasil dibulatkan ke 2 desimal.

- [ ] **Step 1: Tulis test yang gagal**

```swift
@Test func formatsRupiah() {
    #expect(MoneyFormatter.string(1_280_402) == "Rp 1.280.402")
    #expect(MoneyFormatter.string(Decimal(string: "1280.5")!) == "Rp 1.280,50")
    #expect(MoneyFormatter.string(-6_807_247) == "-Rp 6.807.247")
    #expect(MoneyFormatter.string(0) == "Rp 0")
}
@Test func parserEvaluates() throws {
    #expect(try AmountParser.evaluate("19000") == 19000)
    #expect(try AmountParser.evaluate("19000+4500") == 23500)
    #expect(try AmountParser.evaluate("100000-25000×2") == 50000)
    #expect(try AmountParser.evaluate("10÷3") == Decimal(string: "3.33")!)
    #expect(try AmountParser.evaluate("1,5×2") == 3)
}
@Test(arguments: ["12+", "+5", "1,5,2", "×3", "1++2", "abc"])
func parserRejectsMalformed(_ input: String) {
    #expect(throws: AmountParserError.malformed) { try AmountParser.evaluate(input) }
}
@Test func parserRejectsEmptyAndZeroDivision() {
    #expect(throws: AmountParserError.empty) { try AmountParser.evaluate("") }
    #expect(throws: AmountParserError.divisionByZero) { try AmountParser.evaluate("5÷0") }
}
@Test func minorUnitsRoundTrip() {
    #expect(Decimal(string: "19000.25")!.minorUnits == 1_900_025)
    #expect(Decimal(minorUnits: 1_900_025) == Decimal(string: "19000.25")!)
}
```

- [ ] **Step 2:** Jalankan `swift test --package-path Packages/MoneyCore`. Harus FAIL karena simbol belum ada.
- [ ] **Step 3:** Implementasikan. `MoneyFormatter` memakai `Decimal.FormatStyle` locale `id_ID` dengan `precision(.fractionLength(0...2))`. Kalau nilainya bukan bulat, pakai tepat 2 desimal. Prefix `Rp `, dan tanda minus diletakkan sebelum `Rp`. `AmountParser` adalah tokenizer sederhana ditambah evaluasi dua tahap (kali/bagi dulu, lalu tambah/kurang).
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): format rupiah dan parser ekspresi keypad`.

### Task 2: Model SwiftData

**Files:**
- Create: `Models/Profile.swift`, `Models/AssetAccount.swift`, `Models/MoneyCategory.swift`, `Models/MoneyTransaction.swift`, `Models/MoneySchema.swift`
- Test: `Tests/MoneyCoreTests/ModelTests.swift`

**Interfaces:**
- Produces (semua `public`):
  - `@Model Profile`: `id: UUID = UUID()`, `name: String = ""`, `emoji: String = "🙂"`, `colorHex: String = "#FF6B5A"`, `sortOrder: Int = 0`, `createdAt: Date = .now`
  - `enum AssetGroup: String, CaseIterable { case cash, bank, eWallet, creditCard, investment, other }` dengan `displayName` ("Tunai", "Bank", "E-Wallet", "Kartu Kredit", "Investasi", "Lainnya")
  - `@Model AssetAccount`: `id`, `profileID`, `name`, `groupRaw: String = AssetGroup.cash.rawValue`, `initialBalanceMinor: Int64 = 0`, `includeInTotal: Bool = true`, `isArchived: Bool = false`, `sortOrder: Int = 0`, `@Relationship(inverse: \MoneyTransaction.asset) outgoing: [MoneyTransaction]? = []`, `@Relationship(inverse: \MoneyTransaction.toAsset) incoming: [MoneyTransaction]? = []`. Computed `group: AssetGroup`, `initialBalance: Decimal`.
  - `enum CategoryKind: String { case income, expense }`
  - `@Model MoneyCategory`: `id`, `profileID`, `name`, `emoji: String = ""`, `kindRaw`, `isHidden: Bool = false`, `sortOrder: Int = 0`, `parent: MoneyCategory?`, `@Relationship(deleteRule: .cascade, inverse: \MoneyCategory.parent) children: [MoneyCategory]? = []`, `@Relationship(inverse: \MoneyTransaction.category) transactions: [MoneyTransaction]? = []`. Computed `kind: CategoryKind`.
  - `enum TransactionType: String { case income, expense, transfer, adjustment }`
  - `@Model MoneyTransaction`: `id`, `profileID`, `typeRaw`, `amountMinor: Int64 = 0`, `feeMinor: Int64 = 0`, `date: Date = .now`, `category: MoneyCategory?`, `asset: AssetAccount?`, `toAsset: AssetAccount?`, `note: String = ""`, `detail: String = ""`, `recurringRuleID: UUID?`, `occurrenceKey: String?`, `importBatchID: UUID?`, `createdAt`, `updatedAt`. Computed `type: TransactionType`, `amount: Decimal` (get/set), `fee: Decimal`.
  - `enum MoneySchema { static let models: [any PersistentModel.Type]; @MainActor static func makeContainer(inMemory: Bool) throws -> ModelContainer }`. Dengan `inMemory: false`, container memakai `cloudKitDatabase: .none` untuk sementara; Rencana 3 mengaktifkan `.automatic`.

`category` di `MoneyTransaction` boleh menunjuk ke subkategori. Kategori induk transaksi itu didapat dari `category?.parent ?? category`.

- [ ] **Step 1: Tulis test yang gagal**

```swift
@MainActor @Test func persistsAndFiltersByProfile() throws {
    let container = try MoneySchema.makeContainer(inMemory: true)
    let ctx = container.mainContext
    let a = UUID(), b = UUID()
    let tx = MoneyTransaction(profileID: a, type: .expense, amount: 19000, date: .now)
    ctx.insert(tx); ctx.insert(MoneyTransaction(profileID: b, type: .income, amount: 5, date: .now))
    try ctx.save()
    let onlyA = try ctx.fetch(FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.profileID == a }))
    #expect(onlyA.count == 1)
    #expect(onlyA[0].amount == 19000)
    #expect(onlyA[0].amountMinor == 1_900_000)
}
@MainActor @Test func subcategoryRelationship() throws {
    let ctx = try MoneySchema.makeContainer(inMemory: true).mainContext
    let p = UUID()
    let food = MoneyCategory(profileID: p, name: "Makanan", kind: .expense)
    let lunch = MoneyCategory(profileID: p, name: "Makan siang", kind: .expense, parent: food)
    ctx.insert(food); ctx.insert(lunch); try ctx.save()
    #expect(food.children?.count == 1)
}
```

- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan model sesuai Interfaces, dengan convenience init yang dipakai test: `MoneyTransaction(profileID:type:amount:date:)`, `MoneyCategory(profileID:name:kind:emoji:parent:)`, `AssetAccount(profileID:name:group:initialBalance:)`, `Profile(name:emoji:colorHex:)`.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): model SwiftData kompatibel CloudKit`.

### Task 3: ProfileStore

**Files:**
- Create: `Profiles/ProfileStore.swift`
- Test: `Tests/MoneyCoreTests/ProfileStoreTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor @Observable public final class ProfileStore {
    public init(defaults: UserDefaults = .standard)
    public private(set) var activeProfileID: UUID?
    public private(set) var previousProfileID: UUID?
    public func switchTo(_ id: UUID)            // no-op kalau id == aktif
    @discardableResult
    public func switchToPrevious() -> Bool      // false kalau tidak ada previous
    public func handleDeleted(_ id: UUID, fallback: UUID?) // bersihkan aktif/previous
}
```

Key `UserDefaults`: `"activeProfileID"` dan `"previousProfileID"`.

- [ ] **Step 1: Tulis test yang gagal**

Tes memakai `UserDefaults(suiteName: UUID().uuidString)!`.
- `switchesAndRemembersPrevious`: `switchTo(A)`, lalu `switchTo(B)` → aktif == B, previous == A.
- `doubleTapTogglesBackAndForth`: setelah A lalu B, `switchToPrevious()` tiga kali → aktif B→A→B→A dan selalu `true`.
- `persistsAcrossInstances`: store baru dengan suite yang sama membaca aktif dan previous yang sama.
- `switchToPreviousWithoutPrevious`: store baru dengan hanya `switchTo(A)` → `switchToPrevious()` mengembalikan `false` dan aktif tetap A.
- `switchToSameIsNoop`: `switchTo(A)` dua kali → previous tetap nil.
- `previousClearedWhenDeleted`: aktif B, previous A, lalu `handleDeleted(A, fallback: nil)` → previous nil. Kemudian `handleDeleted(B, fallback: C)` → aktif C, previous nil.

- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan `ProfileStore`.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): ProfileStore dengan profil terakhir`.

### Task 4: ProfileService & kategori default

**Files:**
- Create: `Profiles/ProfileService.swift`, `Profiles/DefaultCatalog.swift`
- Test: `Tests/MoneyCoreTests/ProfileServiceTests.swift`

**Interfaces:**
- Consumes: model dari Task 2, `ProfileStore` dari Task 3.
- Produces:

```swift
@MainActor public struct ProfileService {
    public init(context: ModelContext)
    public func bootstrap(store: ProfileStore) throws -> Profile   // buat "Pribadi" kalau belum ada profil; set aktif kalau aktif nil/tidak valid
    public func createProfile(name: String, emoji: String, colorHex: String, copyCategoriesFrom: UUID?) throws -> Profile
    public func deleteProfile(_ id: UUID, store: ProfileStore) throws   // throws ProfileServiceError.lastProfile
    public func profiles() throws -> [Profile]                          // urut sortOrder
    public func update(_ p: Profile, name: String, emoji: String, colorHex: String) throws // throws .emptyName
    public func move(from: IndexSet, to: Int) throws                    // tulis ulang sortOrder
}
public enum ProfileServiceError: Error { case lastProfile, emptyName }
public enum DefaultCatalog {
    public static let expense: [(emoji: String, name: String)]
    public static let income: [(emoji: String, name: String)]
}
```

Isi `DefaultCatalog` sama persis dengan PRD F6, dengan emoji:
- **Pengeluaran:** 🍜 Makanan, 🚕 Transportasi, 🏠 Biaya Sewa Tempat Tinggal, 🪑 Kebutuhan Rumah, 👫 Kehidupan Sosial, 🧥 Pakaian, 💄 Kecantikan, 💊 Kesehatan, 📙 Pendidikan, 🎬 Hiburan, 📈 Invest, 📦 Lainnya.
- **Pendapatan:** 💰 Gaji, 🎁 Bonus, 🏪 Usaha, 📈 Hasil Investasi, 📦 Lainnya.

- [ ] **Step 1: Tulis test yang gagal**
  - `bootstrapCreatesPribadiOnce`: `bootstrap` dua kali → tepat satu profil bernama "Pribadi", 12 kategori pengeluaran, 5 pendapatan, 1 aset "Tunai" bergrup `.cash`, dan store aktif == profil itu.
  - `createProfileWithCopiedCategories`: tambah subkategori "Makan siang" di bawah Makanan profil A. `createProfile(…, copyCategoriesFrom: A)` → profil B punya salinan kategori **beserta** subkategorinya, dengan `id` dan `profileID` baru (bukan objek yang sama).
  - `profileIsolation`: buat transaksi, aset, dan kategori di A dan B. Fetch dengan predicate `profileID == A` → tidak ada objek milik B di ketiga tipe.
  - `deleteProfileRemovesAllData`: hapus B → tidak ada `MoneyTransaction`, `AssetAccount`, atau `MoneyCategory` dengan `profileID == B`. Kalau B sedang aktif, store pindah ke profil lain.
  - `cannotDeleteLastProfile`: memanggil delete dengan hanya satu profil tersisa melempar `.lastProfile`.
  - `emptyNameRejected`: nama `"  "` di `createProfile` maupun `update` melempar `.emptyName`.
  - `moveReordersProfiles`: tiga profil, pindahkan indeks 2 ke 0 → urutan `profiles()` sesuai.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan `ProfileService` dan `DefaultCatalog`.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): ProfileService dengan seeding default`.

### Task 5: Query & ringkasan transaksi

**Files:**
- Create: `Transactions/TransactionQueries.swift`, `Transactions/TransactionSummary.swift`
- Test: `Tests/MoneyCoreTests/TransactionSummaryTests.swift`

**Interfaces:**
- Produces:

```swift
public struct MonthSummary: Equatable { public let income: Decimal; public let expense: Decimal; public var total: Decimal { income - expense } }
public struct DaySection: Identifiable { public let id: Date /* awal hari */; public let income: Decimal; public let expense: Decimal; public let transactions: [MoneyTransaction] /* terbaru di atas */ }
public enum TransactionSummary {
    public static func month(_ txs: [MoneyTransaction]) -> MonthSummary
    public static func daySections(_ txs: [MoneyTransaction], calendar: Calendar) -> [DaySection] // hari terbaru di atas
}
public enum TransactionQueries {
    public static func monthInterval(containing date: Date, calendar: Calendar) -> DateInterval
    public static func descriptor(profileID: UUID, interval: DateInterval) -> FetchDescriptor<MoneyTransaction> // sort date desc
}
```

Aturan:
- Income = jumlah `.income`.
- Expense = jumlah `.expense` + `fee` dari `.transfer`.
- `.transfer` (tanpa fee) dan `.adjustment` tidak dihitung.

- [ ] **Step 1: Tulis test yang gagal**
  - `monthSummaryRules`: income 100.000, expense 19.000 + 23.500, transfer 50.000 dengan fee 2.500, adjustment 10.000 → income 100.000, expense 45.000, total 55.000.
  - `daySectionsGroupAndSort`: tiga transaksi di tanggal 29, 30, 30 → dua section [30, 29]. Section 30 punya 2 transaksi, terbaru di atas, dan totalnya benar.
  - `monthBoundary`: kalender `Asia/Jakarta`. Transaksi 31 Okt 2026 23:59 dan 1 Nov 2026 00:00. `monthInterval` Oktober hanya memuat yang pertama, dan `daySections` memisahkannya ke dua hari.
  - `descriptorFiltersProfileAndMonth` (in-memory container): transaksi profil lain atau bulan lain tidak ikut ter-fetch.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): ringkasan bulan dan grup harian`.

### Task 6: TransactionService

**Files:**
- Create: `Transactions/TransactionService.swift`
- Test: `Tests/MoneyCoreTests/TransactionServiceTests.swift`

**Interfaces:**
- Produces:

```swift
public struct TransactionDraft: Equatable {
    public var type: TransactionType; public var amount: Decimal; public var fee: Decimal
    public var date: Date; public var categoryID: UUID?; public var assetID: UUID?; public var toAssetID: UUID?
    public var note: String; public var detail: String
    public init(type: TransactionType, date: Date)   // amount 0, fee 0, sisanya kosong
    public init(from tx: MoneyTransaction)
}
public enum TransactionValidationError: Error, Equatable { case amountNotPositive, missingCategory, missingAsset, missingTargetAsset, sameAsset, negativeFee }
@MainActor public struct TransactionService {
    public init(context: ModelContext, profileID: UUID)
    public func validate(_ d: TransactionDraft) throws(TransactionValidationError)
    @discardableResult public func create(_ d: TransactionDraft) throws -> MoneyTransaction
    public func update(_ tx: MoneyTransaction, with d: TransactionDraft) throws
    public func delete(_ tx: MoneyTransaction) throws
    @discardableResult public func duplicate(_ tx: MoneyTransaction, on date: Date) throws -> MoneyTransaction
}
```

Aturan validasi:
- `amount > 0`.
- Income/expense wajib punya kategori dan aset.
- Transfer wajib punya aset asal dan tujuan yang berbeda, tanpa kategori.
- `fee >= 0`, dan fee hanya berlaku untuk transfer (diabaikan untuk tipe lain).
- `create` dan `update` mengisi `updatedAt`.
- Kategori dan aset di-resolve hanya dari `profileID` service ini. ID milik profil lain diperlakukan sebagai tidak ada (`missingCategory` / `missingAsset`).

- [ ] **Step 1: Tulis test yang gagal**
  - `createsExpense`: draft valid → tersimpan dengan `profileID`, kategori, dan aset yang benar.
  - Validasi berparameter: amount 0 → `.amountNotPositive`; expense tanpa kategori → `.missingCategory`; transfer tanpa tujuan → `.missingTargetAsset`; transfer dengan asal == tujuan → `.sameAsset`; fee -1 → `.negativeFee`.
  - `rejectsForeignProfileIDs`: kategori milik profil lain → `.missingCategory`.
  - `duplicateCopiesFieldsWithNewDate`: salinan punya `id` berbeda dan `date` baru, sementara field lainnya sama.
  - `updateChangesFieldsAndTimestamp` dan `deleteRemoves`.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): TransactionService dengan validasi`.

### Task 7: Saldo aset & AssetService

**Files:**
- Create: `Assets/BalanceCalculator.swift`, `Assets/AssetService.swift`
- Test: `Tests/MoneyCoreTests/BalanceCalculatorTests.swift`, `Tests/MoneyCoreTests/AssetServiceTests.swift`

**Interfaces:**
- Produces:

```swift
public struct NetWorth: Equatable { public let assets: Decimal; public let liabilities: Decimal; public var total: Decimal { assets + liabilities } }
public enum BalanceCalculator {
    public static func balance(of asset: AssetAccount, transactions: [MoneyTransaction]) -> Decimal
    public static func netWorth(assets: [AssetAccount], transactions: [MoneyTransaction]) -> NetWorth // hanya includeInTotal; saldo negatif → liabilities (bernilai negatif)
    public static func runningBalances(of asset: AssetAccount, transactions: [MoneyTransaction]) -> [(transaction: MoneyTransaction, balanceAfter: Decimal)] // urut tanggal naik
}
@MainActor public struct AssetService {
    public init(context: ModelContext, profileID: UUID)
    public func assets(includeArchived: Bool) throws -> [AssetAccount]   // urut group lalu sortOrder
    public func create(name: String, group: AssetGroup, initialBalance: Decimal) throws -> AssetAccount
    public func adjustBalance(of asset: AssetAccount, to actual: Decimal, on date: Date) throws -> MoneyTransaction? // nil kalau selisih 0
    public func setArchived(_ asset: AssetAccount, _ archived: Bool) throws
}
```

Rumus saldo:

```
saldo = saldo awal
      + Σ income (asset)
      − Σ expense (asset)
      − Σ (transfer amount + fee) keluar
      + Σ transfer amount masuk
      + Σ adjustment (amount bertanda)
```

Transaksi `.adjustment` memakai `amount` bertanda: positif menambah saldo, negatif mengurangi. Ini satu-satunya tipe yang boleh negatif. Ia dibuat oleh `adjustBalance`, bukan lewat `TransactionService`. Catatan otomatisnya `"Penyesuaian saldo"`.

- [ ] **Step 1: Tulis test yang gagal**
  - `balanceRules`: saldo awal 1.000.000, income 500.000, expense 19.000, transfer keluar 200.000 dengan fee 2.500, transfer masuk 50.000, adjustment −8.500 → saldo 1.320.000.
  - `netWorthSplitsLiabilities`: Bank +1.000.000, Kartu Kredit −300.000, aset dengan `includeInTotal == false` +999 → assets 1.000.000, liabilities −300.000, total 700.000.
  - `adjustBalanceCreatesSignedAdjustment`: saldo 100.000, sesuaikan ke 90.000 → adjustment −10.000 dan saldo baru 90.000. Sesuaikan ke 90.000 sekali lagi → `nil`.
  - `archivedHiddenButBalanceKept`: aset yang diarsipkan tidak muncul di `assets(includeArchived: false)`, tetapi saldonya tetap bisa dihitung.
  - `runningBalancesAscending`: saldo berjalan per transaksi benar.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): saldo aset dan penyesuaian`.

### Task 8: CategoryService

**Files:**
- Create: `Categories/CategoryService.swift`
- Test: `Tests/MoneyCoreTests/CategoryServiceTests.swift`

**Interfaces:**
- Produces:

```swift
public enum CategoryServiceError: Error, Equatable { case emptyName, nestingTooDeep, replacementInvalid }
@MainActor public struct CategoryService {
    public init(context: ModelContext, profileID: UUID)
    public func topLevel(kind: CategoryKind, includeHidden: Bool) throws -> [MoneyCategory] // urut sortOrder
    public func create(name: String, emoji: String, kind: CategoryKind, parent: MoneyCategory?) throws -> MoneyCategory
    public func rename(_ c: MoneyCategory, name: String, emoji: String) throws
    public func move(kind: CategoryKind, parent: MoneyCategory?, from: IndexSet, to: Int) throws // tulis ulang sortOrder
    public func setHidden(_ c: MoneyCategory, _ hidden: Bool) throws
    public func usageCount(_ c: MoneyCategory) throws -> Int                // termasuk transaksi subkategori
    public func delete(_ c: MoneyCategory, replacement: MoneyCategory?) throws  // wajib replacement kalau usageCount > 0
}
```

Aturan:
- Subkategori hanya satu level. Parent yang sudah punya parent → `.nestingTooDeep`.
- Replacement harus berjenis sama, bukan kategori yang dihapus, bukan anak dari kategori itu, dan berasal dari profil yang sama. Kalau tidak, `.replacementInvalid`.
- Menghapus induk memindahkan transaksi induk **dan** semua subkategorinya ke replacement, lalu menghapus subkategori.

- [ ] **Step 1: Tulis test yang gagal**
  - `createSubcategory` dan `rejectsThirdLevel`.
  - `reorderRewritesSortOrder`: pindahkan indeks 2 ke 0 → urutan nama sesuai.
  - `deleteUsedRequiresReplacement`: kategori terpakai dengan `replacement: nil` → `.replacementInvalid`.
  - `deleteParentMovesSubcategoryTransactions`: Makanan (2 transaksi) + subkategori Makan siang (3 transaksi), hapus dengan pengganti Lainnya → Lainnya punya 5 transaksi, kategori Makanan dan Makan siang tidak ada lagi, dan tidak ada transaksi dengan `category == nil`.
  - `replacementMustMatchKindAndProfile`.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): kelola kategori dan subkategori`.

### Task 9: NoteSuggester

**Files:**
- Create: `Transactions/NoteSuggester.swift`
- Test: `Tests/MoneyCoreTests/NoteSuggesterTests.swift`

**Interfaces:**
- Produces: `@MainActor public struct NoteSuggester { init(context: ModelContext, profileID: UUID); func suggestions(prefix: String, categoryID: UUID?, limit: Int = 5) throws -> [String] }`

Aturan:
- Pencocokan prefix tidak peka huruf besar/kecil dan diakritik.
- Hasil unik, diurutkan berdasarkan frekuensi lalu tanggal terbaru.
- Kalau `categoryID` diberikan, hanya catatan dari kategori itu.
- Prefix kosong mengembalikan catatan terpopuler.
- Hanya mencari transaksi 180 hari terakhir supaya cepat.

- [ ] **Step 1: Tulis test yang gagal**
  - `suggestsByFrequency`: "makan malam" ×3 dan "makan siang" ×1, prefix "mak" → `["makan malam", "makan siang"]`.
  - `filtersByCategory`.
  - `suggestionsAreProfileScoped`: catatan profil lain tidak pernah muncul.
- [ ] **Step 2:** Jalankan test. Harus FAIL.
- [ ] **Step 3:** Implementasikan.
- [ ] **Step 4:** Jalankan test. Harus PASS.
- [ ] **Step 5:** Commit: `feat(core): saran catatan`.

### Task 10: App shell — TabView native, avatar profil di tab bar, gesture IG

**Files:**
- Modify: `money-manager/money_managerApp.swift`
- Delete: `money-manager/ContentView.swift`
- Create: `App/Color+Hex.swift`, `App/RootView.swift`, `App/ProfileTabIcon.swift`, `App/TabBarGestureBridge.swift`, `App/ProfileSwitcherSheet.swift`, `App/ToastView.swift`

**Interfaces:**
- Consumes: `MoneySchema.makeContainer`, `ProfileStore`, `ProfileService` (Task 2–4).
- Produces:
  - `extension Color { init(hex: String) }` dan `extension UIColor { convenience init(hex: String) }` (format `#RRGGBB`; nilai tidak valid → `.accentColor` / `.tintColor`).
  - `enum AppTab: Hashable { case transactions, statistics, assets, profile }`
  - `@Environment(ProfileStore.self)` tersedia di seluruh view.
  - `@Observable final class ToastCenter { func show(_ text: String) }` di `ToastView.swift`, diinjeksi lewat environment.
  - `enum ProfileTabIcon { static func image(emoji: String, colorHex: String, selected: Bool) -> UIImage }`, yang merender lingkaran 28 pt berisi emoji dengan `withRenderingMode(.alwaysOriginal)`. Saat `selected`, lingkaran diberi ring 2 pt `UIColor.label`.
  - `struct TabBarGestureBridge: UIViewControllerRepresentable { let profileTabIndex: Int; let onDoubleTap: () -> Void; let onLongPress: () -> Void }`.

**Perilaku (PRD F1 dan Pedoman UI):**
- App membuat container (`inMemory: false`), lalu memanggil `ProfileService.bootstrap` saat launch.
- `RootView` adalah `TabView(selection:)` native iOS 26 dengan 4 `Tab`:
  - Transaksi (`list.bullet.rectangle.portrait`), Statistik (`chart.pie`, sementara `ContentUnavailableView` "Segera hadir"), dan Aset (`building.columns`).
  - Tab ke-4 berlabel **nama profil aktif**, dengan ikon `Image(uiImage: ProfileTabIcon.image(...))`.
  - `.tint(Color(hex: profile.colorHex))` dan `.tabBarMinimizeBehavior(.onScrollDown)`.
- `RootView` menyimpan `tabBeforeProfile: AppTab` (tab terakhir yang bukan `.profile`).
- **TabBarGestureBridge:**
  - Dipasang sebagai `.background` tak terlihat di `RootView`. Di `didMove(toParent:)` / `viewDidAppear`, ia menelusuri rantai `parent` untuk menemukan `UITabBarController`, lalu memasang **sekali saja** `UITapGestureRecognizer(numberOfTapsRequired: 2)` dan `UILongPressGestureRecognizer(minimumPressDuration: 0.4)` ke `tabBar`.
  - Keduanya memakai `cancelsTouchesInView = false` tanpa `require(toFail:)`, sehingga tap biasa tetap langsung ditangani sistem.
  - Gesture hanya diproses kalau titik sentuh berada di frame item tab profil. Frame dicari dari subview `tabBar` yang `accessibilityLabel`-nya sama dengan nama profil. Kalau tidak ketemu, pakai cadangan: seperempat lebar paling kanan dari frame konten tab bar.
  - Kalau `UITabBarController` tidak ditemukan, bridge tidak memasang apa pun dan menulis `Logger` warning. Tidak boleh crash.
- **Tap tab profil:** perilaku native, membuka halaman Lainnya (`MoreView`, Task 14; sementara placeholder).
- **Double-tap tab profil:**
  - `store.switchToPrevious()`. Kalau berhasil: `UIImpactFeedbackGenerator(style: .medium)`, toast "Beralih ke **{nama}**" selama 1,5 detik, lalu `selection = tabBeforeProfile`. Ini perlu karena tap pertama sudah membuka tab profil.
  - Kalau tidak ada profil sebelumnya: hanya `UIImpactFeedbackGenerator(style: .light)`, dan tab tetap di tempatnya.
- **Long-press tab profil:**
  - Membuka `ProfileSwitcherSheet`: `.presentationDetents([.medium, .large])`, `NavigationStack` dengan judul "Ganti Profil", dan `List` inset grouped berisi baris avatar + nama + centang di profil aktif, plus section "+ Tambah profil".
  - "+ Tambah profil" membuka form (nama, emoji, `ColorPicker` dari 8 warna preset, dan `Picker` "Salin kategori dari") dengan toolbar Batal/Simpan.
  - Tap profil → switch, haptic, toast, lalu sheet ditutup.
- **Toast:** kapsul kecil di atas tab bar, latar `.regularMaterial`, teks `.subheadline`. Muncul dan hilang dengan `.opacity`, dan tanpa geser kalau Reduce Motion aktif.
- **Aksesibilitas:** tab profil diberi `.accessibilityActions` "Ganti profil" (buka switcher) dan "Profil terakhir" (switch ke previous), supaya pengguna VoiceOver tetap bisa memakai kedua fungsi itu tanpa gesture.

- [ ] **Step 1 (SPIKE, ≤ 1 jam):** Buat `TabBarGestureBridge` + `ProfileTabIcon` minimal di `RootView`, dengan 4 tab dan print di handler. Jalankan di **iOS 26.3** dan **iOS 27.2**, lalu jawab tiga pertanyaan:
  - (a) Apakah ikon avatar berwarna tampil apa adanya, tidak dijadikan template monokrom?
  - (b) Apakah double-tap dan long-press di tab profil terdeteksi, tanpa terpicu di tab lain?
  - (c) Apakah tap biasa ke semua tab masih instan?

  Catat jawabannya di pesan commit spike.

  **Kalau (a) gagal:** ikon tab memakai SF Symbol `person.crop.circle.fill`, dan avatar emoji pindah ke header halaman Lainnya. Laporkan ke pengguna sebelum lanjut.

  **Kalau (b) gagal di salah satu versi iOS:** STOP dan laporkan ke pengguna, karena ini mengubah keputusan desain.
- [ ] **Step 2:** Implementasikan perilaku lengkap di atas. Hapus `ContentView.swift`.
- [ ] **Step 3:** Jalankan perintah build app. Harus `** BUILD SUCCEEDED **`.
- [ ] **Step 4:** Verifikasi manual di simulator iOS 26.3, dengan screenshot:
  - (a) Launch pertama menampilkan avatar "Pribadi" di tab bar Liquid Glass.
  - (b) Long-press avatar membuka switcher. Tambah "Bisnis" → aktif jadi Bisnis, toast muncul, label tab dan tint berubah.
  - (c) Dari tab Transaksi, double-tap avatar → pindah ke Pribadi dan kembali ke tab Transaksi. Double-tap lagi → Bisnis.
  - (d) Tap sekali → halaman Lainnya terbuka.
  - (e) Matikan lalu buka ulang app → profil aktif tetap.
  - (f) Dark mode dan iPhone 16e tetap rapi.
  - (g) VoiceOver: aksi "Ganti profil" dan "Profil terakhir" tersedia.
- [ ] **Step 5:** Verifikasi fallback. Untuk sementara, paksa bridge tidak menemukan `UITabBarController` (mis. flag debug). App harus tetap jalan normal tanpa gesture, dan aksi VoiceOver tetap berfungsi. Kembalikan flag setelahnya.
- [ ] **Step 6:** Commit: `feat(app): TabView native dengan avatar profil dan gesture ala IG`.

### Task 11: Daftar transaksi Harian

**Files:**
- Create: `Transactions/TransactionListView.swift`, `Transactions/DailySectionView.swift`

**Interfaces:**
- Consumes: `TransactionQueries.descriptor`, `TransactionSummary`, `MoneyFormatter`, `ProfileStore.activeProfileID`.
- Produces: `TransactionListView` (konten tab Transaksi), yang membuka `TransactionFormView` (Task 12) lewat tombol + dan tap baris.

Perilaku (PRD F3, Harian):
- **Header:**
  - Strip warna profil, nama profil, navigasi `‹ Okt 2026 ›` (format bulan `MMM yyyy` locale id_ID), dan tiga kolom Pendapatan (biru), Pengeluaran (merah), Total.
  - Segmented control Harian | Kalender | Bulanan. Kalender dan Bulanan untuk sementara placeholder (Rencana 3).
- **Isi:**
  - `List` dengan section per hari. Header section: tanggal besar, badge hari (Sab biru, Min merah, lainnya abu-abu), lalu total income dan expense hari itu.
  - Baris: emoji + nama kategori induk, catatan (atau nama kategori kalau catatan kosong), nama aset, dan nominal. Warna nominal: biru untuk income, merah untuk expense, abu-abu untuk transfer (nama aset ditampilkan "Bank → Spay"), abu-abu miring untuk adjustment.
- **Interaksi:**
  - `.swipeActions(edge: .trailing)` Hapus (merah, `role: .destructive`) dengan `confirmationDialog`. `.swipeActions(edge: .leading)` Duplikat.
  - Swipe horizontal pada area daftar memindah bulan.
  - `@Query` dibangun ulang ketika `activeProfileID` atau bulan berubah. Gunakan subview yang menerima descriptor lewat init, sesuai pola dinamis `@Query`.
- **State kosong:** `ContentUnavailableView("Belum ada transaksi", systemImage: "tray", description: "di {bulan}")` dengan tombol "Catat transaksi".
- Tombol + mengambang di kanan bawah, di atas tab bar: `Button` dengan `Image(systemName: "plus")`, `.buttonStyle(.glassProminent)`, 56 pt, `accessibilityLabel("Tambah transaksi")`. Tombol ini membuka form tambah.
- Judul layar memakai `navigationTitle("Transaksi")` large title. Ikon cari (`magnifyingglass`) dan filter disiapkan di toolbar untuk Rencana 4, untuk sementara disembunyikan.
- State kosong memakai `ContentUnavailableView`.

- [ ] **Step 1:** Implementasikan.
- [ ] **Step 2:** Build. Harus BUILD SUCCEEDED.
- [ ] **Step 3:** Verifikasi di simulator dengan data dari Task 12 (atau seed sementara lewat `#Preview`):
  - Pindah bulan memperbarui ringkasan.
  - Ganti profil lewat double-tap mengganti seluruh isi daftar.
  - Ringkasan bulan sama dengan jumlah header harian.
- [ ] **Step 4:** Commit: `feat(app): daftar transaksi harian`.

### Task 12: Form transaksi & keypad kalkulator

**Files:**
- Create: `Transactions/TransactionFormView.swift`, `Transactions/CalculatorKeypad.swift`, `Transactions/PickerSheets.swift`

**Interfaces:**
- Consumes: `TransactionDraft`, `TransactionService`, `AmountParser`, `MoneyFormatter`, `CategoryService.topLevel`, `AssetService.assets`, `NoteSuggester`.
- Produces: `TransactionFormView(mode: .create(defaultDate: Date) | .edit(MoneyTransaction))`.

Perilaku (PRD F2):
- Judul sesuai jenis transaksi. Segmented Pendapatan | Pengeluaran | Transfer. Subjudul kecil "Profil: {nama}".
- **Baris field:**
  - Tanggal (DatePicker tanggal + jam).
  - Total (menampilkan ekspresi mentah selama diketik).
  - Kategori, atau Dari/Ke untuk transfer.
  - Aset, Catatan, dan Deskripsi.
  - Biaya (hanya untuk transfer, juga lewat keypad).
- **CalculatorKeypad:**
  - Grid 4 kolom sesuai screenshot PRD: baris `+ - × ÷`, `7 8 9 =`, `4 5 6 ,`, `1 2 3 ⌫`, ` 0  Ya`.
  - `=` mengganti ekspresi dengan hasil `AmountParser.evaluate`.
  - `Ya` mengevaluasi ekspresi, lalu memindah fokus ke Kategori (atau Dari).
  - Error ditampilkan inline di bawah Total: "Format tidak valid" atau "Tidak bisa dibagi nol".
- Pemilih kategori dan aset berupa sheet bawah berbentuk grid. Tap kategori yang punya subkategori → tampilkan subkategorinya plus opsi "{induk} saja". Setelah kategori dipilih, fokus otomatis pindah ke Aset.
- Catatan menampilkan chip saran dari `NoteSuggester` di atas keyboard.
- **Penyajian:** sheet `.presentationDetents([.large])` dengan `NavigationStack`. Toolbar **Batal** di kiri atas dan **Simpan** (`.confirmationAction`) di kanan atas. Field ditampilkan sebagai `Form` inset grouped. Keypad tampil sebagai panel bawah di safe area, menggantikan keyboard sistem untuk field Total/Biaya, dan Catatan/Deskripsi memakai keyboard sistem biasa.
- **Tombol:**
  - Mode create: tombol sekunder **Simpan & Lanjut** di atas keypad (form direset kecuali tanggal dan jenis).
  - Mode edit: section paling bawah berisi **Duplikat** (tanggal hari ini) dan **Hapus** (merah, dengan `confirmationDialog`).
  - **Simpan** nonaktif selama `validate` melempar error.
  - Haptic `.success` saat tersimpan.
- **Keypad:** tombol 44 pt ke atas dengan latar `Color(.secondarySystemBackground)`, angka `.title2` `.monospacedDigit()`, dan **Ya** berwarna tint profil. Setiap tombol punya label VoiceOver ("tambah", "kali", "hapus", dst.).

- [ ] **Step 1:** Implementasikan.
- [ ] **Step 2:** Build. Harus BUILD SUCCEEDED.
- [ ] **Step 3:** Verifikasi di simulator:
  - Catat "makan siang" 19000+4500 → tersimpan 23.500 di daftar.
  - Transfer Bank → Tunai 100.000 dengan biaya 2.500 → ringkasan pengeluaran bertambah 2.500 saja.
  - Simpan & Lanjut mempertahankan tanggal.
  - Edit, duplikat, dan hapus bekerja.
  - Picker tidak pernah menampilkan kategori atau aset dari profil lain.
  - Waktu catat satu transaksi dari tap + sampai simpan **< 10 detik**.
- [ ] **Step 4:** Commit: `feat(app): form transaksi dan keypad kalkulator`.

### Task 13: Layar Aset

**Files:**
- Create: `Assets/AssetListView.swift`, `Assets/AssetDetailView.swift`, `Assets/AssetFormView.swift`

**Interfaces:**
- Consumes: `AssetService`, `BalanceCalculator`, `MoneyFormatter`.

Perilaku (PRD F5):
- **Header:** Aset, Liabilitas, dan Total dari `netWorth`.
- **Daftar:** dikelompokkan per `AssetGroup.displayName` dengan subtotal per grup dan saldo per aset.
- **Tombol + / edit** membuka `AssetFormView`: nama, grup, saldo awal (pakai `CalculatorKeypad`), toggle "Masukkan ke total", dan toggle arsip.
- **Toggle "Tampilkan arsip"** di toolbar.
- **Detail aset:**
  - Riwayat transaksi per bulan dengan saldo berjalan (`runningBalances`).
  - Tombol "Sesuaikan saldo" membuka input saldo sebenarnya → `adjustBalance`. Konfirmasi menampilkan selisihnya.

- [ ] **Step 1:** Implementasikan.
- [ ] **Step 2:** Build. Harus BUILD SUCCEEDED.
- [ ] **Step 3:** Verifikasi di simulator:
  - Saldo aset cocok dengan perhitungan manual dari transaksi Task 12.
  - Kartu Kredit bersaldo negatif masuk Liabilitas.
  - Sesuaikan saldo mengubah saldo, tetapi **tidak** mengubah ringkasan Pendapatan/Pengeluaran di tab Transaksi.
  - Aset yang diarsipkan hilang dari picker form.
- [ ] **Step 4:** Commit: `feat(app): layar aset dan penyesuaian saldo`.

### Task 14: Lainnya — kelola profil & kategori

**Files:**
- Create: `More/MoreView.swift`, `More/ProfileManagementView.swift`, `More/CategoryManagementView.swift`

**Interfaces:**
- Consumes: `ProfileService`, `ProfileStore`, `CategoryService`.

Perilaku:
- **MoreView** berisi daftar menu:
  - Profil, Kategori.
  - Placeholder nonaktif untuk Import/Export, Transaksi Berulang, dan Keamanan, berlabel "Segera hadir".
  - "Tentang" yang menampilkan versi.
- **ProfileManagementView:**
  - Ubah nama, emoji, dan warna; tambah profil; urutkan dengan drag.
  - Hapus dengan alert berisi text field yang mewajibkan pengguna mengetik nama profil persis sebelum tombol "Hapus" aktif.
  - Profil terakhir tidak bisa dihapus (tombol disembunyikan).
  - Setelah menghapus, panggil `store.handleDeleted`.
- **CategoryManagementView:**
  - Segmented Pengeluaran | Pendapatan, dengan daftar yang bisa di-drag (`move`).
  - Tap kategori membuka edit nama/emoji dan daftar subkategorinya (tambah, ubah, urutkan).
  - Swipe untuk sembunyikan/tampilkan.
  - Hapus menampilkan "Dipakai di N transaksi" dan meminta memilih pengganti kalau N > 0.

- [ ] **Step 1:** Implementasikan.
- [ ] **Step 2:** Build. Harus BUILD SUCCEEDED.
- [ ] **Step 3:** Verifikasi di simulator:
  - Kategori yang disembunyikan hilang dari picker form, tapi transaksi lamanya tetap tampil.
  - Menghapus kategori terpakai memindahkan transaksinya.
  - Menghapus profil Bisnis menghapus datanya dan memindahkan avatar ke Pribadi.
  - Double-tap setelahnya tidak crash (hanya haptic ringan).
- [ ] **Step 4:** Jalankan `swift test --package-path Packages/MoneyCore` dan build app sekali lagi. Semua test harus PASS dan build harus BUILD SUCCEEDED.
- [ ] **Step 5:** Commit: `feat(app): kelola profil dan kategori`.
