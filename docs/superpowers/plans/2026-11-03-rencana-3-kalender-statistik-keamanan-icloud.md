# Rencana 3 — Kalender, Bulanan, Statistik, Face ID & iCloud

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Melengkapi tab Transaksi dengan tampilan Kalender dan Bulanan, mengisi tab Statistik (donut per kategori, rincian, tren 6 bulan), mengunci aplikasi dengan Face ID, dan menyalakan sinkronisasi iCloud tanpa membuat profil ganda di perangkat baru.

**Architecture:** Sama dengan Rencana 1. Semua perhitungan (grid kalender, ringkasan per bulan, statistik, aturan kunci, pembersihan profil ganda) ada di `Packages/MoneyCore` dan dites dengan `swift test`. Target app hanya berisi view SwiftUI, LocalAuthentication, dan konfigurasi iCloud.

**Tech Stack:** Swift 6.4, SwiftUI (iOS 26 Liquid Glass), Swift Charts, SwiftData + CloudKit, LocalAuthentication, Swift Testing, Xcode 27.2.

**Spec:** [`docs/PRD-money-manager.md`](../../PRD-money-manager.md). Rencana ini mencakup F3 (Kalender, Bulanan), F4, F12, dan F13.

**Lanjutan dari:** [Rencana 1](2026-11-01-rencana-1-fondasi-pencatatan.md). Semua Global Constraints Rencana 1 tetap berlaku.

## Global Constraints (tambahan)

- Statistik memakai aturan yang sama dengan `TransactionSummary`: Pendapatan = `.income`; Pengeluaran = `.expense` + `fee` transfer. Transfer tanpa fee dan adjustment tidak dihitung. Fee transfer tampil sebagai baris **"Biaya transfer"** di statistik Pengeluaran, sehingga total Statistik selalu sama dengan total tab Transaksi untuk periode yang sama (PRD F4).
- Statistik dikelompokkan per **kategori induk**. Transaksi subkategori dihitung ke induknya. Transaksi tanpa kategori masuk **"Tanpa kategori"**.
- Kalender memakai `Calendar.current` (minggu dimulai sesuai `firstWeekday` perangkat). Semua fungsi inti menerima `calendar` sebagai parameter supaya bisa dites dengan `Asia/Jakarta`.
- Pengaturan kunci aplikasi disimpan di `UserDefaults` (per perangkat, tidak di-sync), sesuai PRD bagian 9.
- `MoneySchema.makeContainer(inMemory: false)` memakai `cloudKitDatabase: .automatic`. Tanpa entitlement iCloud, SwiftData tetap berjalan lokal, jadi build tanpa akun developer berbayar tidak rusak.
- **Jangan** memanggil `CKContainer` di kode app. Status iCloud dibaca dari `FileManager.default.ubiquityIdentityToken`, yang aman walaupun entitlement belum ada.
- Verifikasi UI di simulator iPhone 17 Pro (light dan dark). Screenshot sebagai bukti.

## Review Focus

1. **Total Statistik ≠ total Transaksi.** Untuk bulan yang sama, total Pengeluaran Statistik harus sama persis dengan header tab Transaksi, termasuk fee transfer. Dites di Task 2 (`expenseTotalMatchesMonthSummary`).
2. **Profil ganda setelah iCloud aktif.** Perangkat baru membuat "Pribadi" kosong sebelum data iCloud datang. Profil kosong yang namanya sama dengan profil lain harus dihapus, dan profil yang punya transaksi tidak pernah dihapus. Dites di Task 4.
3. **Batas minggu, bulan, tahun.** 31 Des 23:59 vs 1 Jan 00:00, minggu yang melewati pergantian bulan, Februari tahun kabisat. Dites di Task 1 dan Task 2.
4. **Kunci aplikasi lolos.** Konten tidak boleh terlihat di app switcher saat kunci aktif, dan aplikasi harus terkunci lagi setelah di background lebih lama dari batas. Dites di Task 3 dan dicek manual di Task 8.

---

## Struktur File

```
Packages/MoneyCore/Sources/MoneyCore/
├── Transactions/TransactionQueries.swift     — + yearInterval
├── Transactions/TransactionSummary.swift     — + monthRows, dayTotals
├── Transactions/CalendarGrid.swift           — baru: minggu-minggu dalam satu bulan
├── Statistics/StatsPeriod.swift              — baru: Mingguan/Bulanan/Tahunan/Rentang
├── Statistics/StatisticsCalculator.swift     — baru: porsi kategori, subkategori, tren
├── Security/AppLockPolicy.swift              — baru: kapan harus mengunci + pengaturan
├── Profiles/ProfileService.swift             — + removeEmptyDuplicates
└── Models/MoneySchema.swift                  — cloudKitDatabase .automatic

money-manager/
├── Transactions/TransactionListView.swift    — mode Kalender & Bulanan, navigasi tahun
├── Transactions/CalendarMonthView.swift      — baru
├── Transactions/MonthlyYearView.swift        — baru
├── Statistics/StatisticsView.swift           — baru: tab Statistik
├── Statistics/CategoryStatsDetailView.swift  — baru
├── Security/AppLockController.swift          — baru: LocalAuthentication + scenePhase
├── Security/LockScreenView.swift             — baru
├── More/SecuritySettingsView.swift           — baru
├── More/MoreView.swift                       — Keamanan & status iCloud
├── App/RootView.swift                        — tab Statistik
├── money_managerApp.swift                    — overlay kunci + pembersihan profil ganda
└── money-manager.entitlements                — baru: iCloud CloudKit + push
```

---

### Task 1: Kalender & ringkasan tahunan (core)

**Files:**
- Create: `Transactions/CalendarGrid.swift`
- Modify: `Transactions/TransactionQueries.swift`, `Transactions/TransactionSummary.swift`
- Test: `CalendarGridTests.swift`, tambahan di `TransactionSummaryTests.swift`

**Interfaces:**

```swift
public enum CalendarGrid {
    /// Baris minggu untuk bulan yang memuat `month`. Setiap baris berisi 7 sel; sel di luar bulan bernilai nil.
    public static func weeks(for month: Date, calendar: Calendar) -> [[Date?]]
    /// Simbol hari pendek sesuai `firstWeekday` kalender, mis. ["Min", "Sen", ...].
    public static func weekdaySymbols(calendar: Calendar) -> [String]
}
public struct DayTotals: Equatable { public let income: Decimal; public let expense: Decimal }
public struct MonthRow: Identifiable, Equatable { public let id: Date /* awal bulan */; public let income: Decimal; public let expense: Decimal; public var total: Decimal { income - expense } }
extension TransactionQueries { public static func yearInterval(containing: Date, calendar: Calendar) -> DateInterval }
extension TransactionSummary {
    public static func dayTotals(_ txs: [MoneyTransaction], calendar: Calendar) -> [Date: DayTotals] // key = awal hari
    public static func monthRows(_ txs: [MoneyTransaction], year: Date, calendar: Calendar) -> [MonthRow] // selalu 12, Jan → Des
}
```

- [ ] **Step 1: Test gagal**
  - `weeksNovember2026`: Nov 2026, firstWeekday 1 → 1 Nov jatuh hari Minggu, jadi sel pertama baris pertama = 1 Nov; setiap baris 7 sel; jumlah sel non-nil 30.
  - `weeksRespectFirstWeekday`: firstWeekday 2 menggeser kolom.
  - `weeksFebruaryLeapYear`: Feb 2028 punya 29 hari.
  - `monthRowsAlwaysTwelve`: transaksi di Jan dan Des → 12 baris, bulan kosong bernilai 0; 31 Des 23:59 masuk Des, 1 Jan tahun berikutnya tidak ikut.
  - `dayTotalsMatchDaySections`: hasil sama dengan `daySections`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementasi. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): grid kalender dan ringkasan per bulan`.

### Task 2: Statistik (core)

**Files:** Create `Statistics/StatsPeriod.swift`, `Statistics/StatisticsCalculator.swift`. Test `StatsPeriodTests.swift`, `StatisticsCalculatorTests.swift`.

**Interfaces:**

```swift
public enum StatsPeriodKind: String, CaseIterable, Sendable { case weekly, monthly, yearly, range }
public struct StatsPeriod: Equatable {
    public var kind: StatsPeriodKind
    public var interval: DateInterval            // end eksklusif
    public static func containing(_ date: Date, kind: StatsPeriodKind, calendar: Calendar) -> StatsPeriod // range → bulan berjalan
    public static func range(from: Date, to: Date, calendar: Calendar) -> StatsPeriod // inklusif sampai akhir hari `to`
    public func shifted(by: Int, calendar: Calendar) -> StatsPeriod  // range: geser sepanjang durasinya (dalam hari)
}
public struct CategoryShare: Identifiable, Equatable {
    public let id: UUID?          // nil = "Tanpa kategori"; StatisticsCalculator.transferFeeID = "Biaya transfer"
    public let name: String; public let emoji: String
    public let amount: Decimal; public let fraction: Double  // 0...1
}
public struct TrendPoint: Identifiable, Equatable { public let id: Date /* awal bulan */; public let amount: Decimal }
public enum StatisticsCalculator {
    public static let transferFeeID: UUID
    public static func breakdown(_ txs: [MoneyTransaction], kind: CategoryKind) -> [CategoryShare] // besar → kecil
    public static func total(_ txs: [MoneyTransaction], kind: CategoryKind) -> Decimal
    public static func subcategoryBreakdown(_ txs: [MoneyTransaction], parentID: UUID?, kind: CategoryKind) -> [CategoryShare] // transaksi langsung di induk = baris induk itu sendiri
    public static func transactions(_ txs: [MoneyTransaction], shareID: UUID?, kind: CategoryKind) -> [MoneyTransaction] // terbaru di atas
    public static func trend(_ txs: [MoneyTransaction], shareID: UUID?, kind: CategoryKind, months: Int, endingAt: Date, calendar: Calendar) -> [TrendPoint] // selalu `months` titik
}
```

- [ ] **Step 1: Test gagal**
  - `periodWeeklyCrossesMonth`, `periodYearlyBoundary`, `periodShift` (bulanan Jan → Des tahun lalu), `rangeInclusiveEnd`.
  - `breakdownGroupsByParent`: subkategori "Makan > Siang" dihitung ke "Makan"; urutan besar ke kecil; `fraction` total 1.
  - `breakdownSkipsTransfer`, `transferFeeAppearsAsRow`, `uncategorizedRow`.
  - `expenseTotalMatchesMonthSummary`: `total(.expense)` == `TransactionSummary.month(...).expense`.
  - `trendSixMonths`: 6 titik, bulan kosong 0, titik terakhir = bulan `endingAt`.
- [ ] **Step 2–4:** FAIL → implementasi → PASS.
- [ ] **Step 5:** Commit `feat(core): perhitungan statistik per kategori`.

### Task 3: Aturan kunci aplikasi (core)

**Files:** Create `Security/AppLockPolicy.swift`. Test `AppLockPolicyTests.swift`.

```swift
@MainActor @Observable
public final class AppLockSettings {           // UserDefaults: "appLockEnabled", "appLockGraceSeconds"
    public init(defaults: UserDefaults = .standard)
    public var isEnabled: Bool                  // default false
    public var graceSeconds: Int                // default 60; pilihan: 0, 60, 300, 900
    public static let graceOptions: [Int]
}
public enum AppLockPolicy {
    /// Saat kembali ke foreground: kunci bila aktif dan sudah di background ≥ grace. Tanpa `backgroundedAt` (cold start) selalu kunci bila aktif.
    public static func shouldLock(enabled: Bool, backgroundedAt: Date?, now: Date, graceSeconds: Int) -> Bool
}
```

- [ ] Test: `disabledNeverLocks`, `coldStartLocks`, `withinGraceStaysOpen`, `pastGraceLocks`, `zeroGraceAlwaysLocks`, `settingsPersist`.
- [ ] Commit `feat(core): aturan kunci aplikasi`.

### Task 4: iCloud aktif & pembersihan profil ganda (core)

**Files:** Modify `Models/MoneySchema.swift`, `Profiles/ProfileService.swift`. Test di `ProfileServiceTests.swift`.

```swift
extension ProfileService {
    /// Menghapus profil tanpa transaksi yang namanya (case-insensitive, trim) sama dengan profil lain.
    /// Dari sekumpulan profil bernama sama: bila ada yang punya transaksi, semua yang kosong dihapus;
    /// bila semuanya kosong, yang `createdAt` paling awal dipertahankan. Aset & kategori milik profil yang dihapus ikut dihapus.
    /// Memanggil `store.handleDeleted` untuk setiap profil terhapus. Mengembalikan jumlah profil yang dihapus.
    @discardableResult public func removeEmptyDuplicates(store: ProfileStore) throws -> Int
}
```

- [ ] Test: `duplicateEmptyRemovedWhenOtherHasData` (aktif dipindah ke profil berdata), `profileWithTransactionsNeverRemoved` (dua profil bernama sama, keduanya berdata → tidak ada yang dihapus), `allEmptyKeepsOldest`, `differentNamesUntouched`, `removedProfileDataDeleted`.
- [ ] `MoneySchema`: `cloudKitDatabase: inMemory ? .none : .automatic`. Perbarui komentar.
- [ ] Commit `feat(core): sinkron iCloud dan pembersihan profil ganda`.

### Task 5: Tampilan Kalender

**Files:** Create `Transactions/CalendarMonthView.swift`. Modify `TransactionListView.swift`.

- Grid 7 kolom dari `CalendarGrid.weeks`. Baris judul hari dari `weekdaySymbols` (Minggu merah, Sabtu biru, sama dengan badge Harian).
- Setiap sel: nomor tanggal, lalu pendapatan (biru) dan pengeluaran (merah) singkat bila tidak 0. Hari ini ditandai lingkaran tint. Tanggal terpilih diberi latar tint lembut.
- Tap tanggal memilih tanggal itu dan menampilkan daftar transaksinya di bawah grid (memakai `DailySectionView`, termasuk swipe hapus/duplikat dan tap untuk edit).
- Tombol + memakai tanggal terpilih (siang hari itu, atau `now` bila hari ini). Pindah bulan menghapus pilihan.
- Swipe kiri/kanan di grid berpindah bulan, sama dengan header.
- Nominal sel memakai format ringkas tanpa "Rp" (mis. `1,2jt`, `850rb`) agar muat; VoiceOver membacakan nominal lengkap.
- [ ] Build, verifikasi di simulator, commit `feat(app): tampilan kalender`.

### Task 6: Tampilan Bulanan

**Files:** Create `Transactions/MonthlyYearView.swift`. Modify `TransactionListView.swift`.

- Saat mode Bulanan, navigator header menampilkan **tahun** (`‹ 2026 ›`) dan menggeser per tahun; ringkasan header berisi total setahun.
- Daftar 12 bulan (`MonthRow`), bulan terbaru di atas, bulan depan (setelah bulan ini) disembunyikan bila tahun berjalan. Setiap baris: nama bulan, pendapatan, pengeluaran, total.
- Tap bulan → mode Harian pada bulan itu.
- [ ] Build, verifikasi, commit `feat(app): tampilan bulanan`.

### Task 7: Tab Statistik

**Files:** Create `Statistics/StatisticsView.swift`, `Statistics/CategoryStatsDetailView.swift`. Modify `App/RootView.swift`.

- Large title "Statistik". Header: menu periode (Mingguan/Bulanan/Tahunan/Rentang) + navigator `‹ label ›`; Rentang membuka sheet dua `DatePicker`.
- Segmented Pendapatan / Pengeluaran dengan total di masing-masing segmen.
- Donut `SectorMark(angle:innerRadius: .ratio(0.6))`, warna dari palet tetap per urutan; total periode di tengah donut.
- Daftar kategori: badge persen berwarna sama dengan sektor, emoji + nama, nominal. Tap → `CategoryStatsDetailView`.
- Detail: grafik batang tren 6 bulan (`BarMark`, bulan berjalan di-highlight), rincian subkategori bila ada, lalu daftar transaksi periode (tap untuk edit).
- State kosong: `ContentUnavailableView("Belum ada data", systemImage: "chart.pie")`.
- [ ] Build, verifikasi (bandingkan total dengan tab Transaksi untuk bulan yang sama), commit `feat(app): tab statistik`.

### Task 8: Kunci Face ID

**Files:** Create `Security/AppLockController.swift`, `Security/LockScreenView.swift`, `More/SecuritySettingsView.swift`. Modify `money_managerApp.swift`, `More/MoreView.swift`, project (`INFOPLIST_KEY_NSFaceIDUsageDescription`).

- `AppLockController` (`@Observable`): `isLocked`, `unlock()` memakai `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (Face ID dengan fallback passcode), mencatat `backgroundedAt` dan memakai `AppLockPolicy.shouldLock` saat `scenePhase` kembali `.active`.
- Overlay di `money_managerApp`: saat `isLocked` tampil `LockScreenView` (ikon app, "Duitku terkunci", tombol "Buka dengan Face ID"); minta otomatis saat muncul. Saat `scenePhase != .active` dan kunci aktif, tampil penutup buram (`.ultraThinMaterial` penuh layar) supaya konten tidak terlihat di app switcher.
- Lainnya → Keamanan: toggle "Kunci dengan Face ID" (menyalakan perlu autentikasi berhasil dulu), picker "Kunci ulang setelah": Langsung / 1 menit / 5 menit / 15 menit. Bila perangkat tidak punya biometrik/passcode, toggle nonaktif dengan penjelasan.
- [ ] Build, verifikasi di simulator (Features → Face ID → Enrolled, Matching Face), commit `feat(app): kunci aplikasi dengan face id`.

### Task 9: iCloud

**Files:** Create `money-manager/money-manager.entitlements`. Modify project (`CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_KEY_UIBackgroundModes = remote-notification`), `money_managerApp.swift`, `More/MoreView.swift`.

- Entitlement: `com.apple.developer.icloud-services = [CloudKit]`, `com.apple.developer.icloud-container-identifiers = [iCloud.pakenanya.money-manager]`, `aps-environment = development`.
- Lainnya → baris "iCloud": "Aktif" (hijau) bila `ubiquityIdentityToken != nil`, selain itu "Tidak tersedia — data tersimpan di iPhone ini" dengan footer cara mengaktifkan.
- `removeEmptyDuplicates` dipanggil setelah bootstrap dan setiap `NSPersistentStoreRemoteChange` (debounce 2 detik).
- **[MANUAL PENGGUNA] bila build gagal karena provisioning:** di Xcode buka target → Signing & Capabilities → `+ Capability` → iCloud (centang CloudKit, container `iCloud.pakenanya.money-manager`) dan Background Modes (Remote notifications). iCloud butuh Apple Developer Program berbayar; tanpanya aplikasi tetap jalan lokal.
- [ ] Build, verifikasi status di Lainnya, commit `feat(app): sinkronisasi icloud`.
