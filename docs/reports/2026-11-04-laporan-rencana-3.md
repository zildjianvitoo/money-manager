# Laporan Rencana 3 — Kalender, Bulanan, Statistik, Face ID & iCloud

**Tanggal:** 4 November 2026
**Branch:** `feat/rencana-3` (dibuat dari `main` setelah PR #1 di-merge)
**Rencana:** [`docs/superpowers/plans/2026-11-03-rencana-3-kalender-statistik-keamanan-icloud.md`](../superpowers/plans/2026-11-03-rencana-3-kalender-statistik-keamanan-icloud.md)

## Ringkasan

Semua task Rencana 3 (Task 1–9) sudah selesai, dites, dan dicek di simulator iPhone 17 Pro.

| Fitur | Status | Catatan |
|---|---|---|
| Tampilan **Kalender** di tab Transaksi | Selesai | Grid bulan + total per hari, tap tanggal → daftar transaksi hari itu |
| Tampilan **Bulanan** di tab Transaksi | Selesai | 12 bulan per tahun, navigasi tahun, tap bulan → Harian bulan itu |
| Tab **Statistik** | Selesai | Donut per kategori, rincian kategori, tren 6 bulan |
| **Kunci Face ID** | Selesai | Toggle di Lainnya → Keamanan, kunci ulang setelah 0/1/5/15 menit |
| **Sinkronisasi iCloud** | Kode selesai, butuh aktivasi | Lihat bagian "Yang perlu kamu lakukan" |

- Unit test: **127 lulus** (sebelumnya 98, bertambah 29).
- Build app: `** BUILD SUCCEEDED **`.

## Yang bisa kamu coba sekarang

### Tab Transaksi
- **Kalender:**
  - Setiap tanggal menampilkan pendapatan (biru) dan pengeluaran (merah) dalam format ringkas, mis. `55,8rb` atau `1,2jt`.
  - Tap tanggal untuk melihat daftar transaksi hari itu di bawah grid. Tap lagi untuk membatalkan pilihan.
  - Tombol **+** memakai tanggal yang sedang dipilih.
  - Nama hari selalu dalam bahasa Indonesia (Min, Sen, …), apa pun bahasa iPhone.
- **Bulanan:**
  - Header berubah menjadi tahun (`‹ 2026 ›`), dan ringkasannya berisi total setahun.
  - Bulan yang belum terjadi di tahun berjalan disembunyikan.
  - Tap sebuah bulan untuk langsung membuka tampilan Harian bulan itu.

### Tab Statistik
- **Periode:** Mingguan, Bulanan, Tahunan, atau Rentang tanggal sendiri, dengan tombol `‹ ›` untuk berpindah periode.
- **Pendapatan / Pengeluaran:** pilih salah satu; totalnya langsung terlihat di tombolnya.
- **Donut chart:** total periode tampil di tengah. Lebih dari 8 kategori digabung jadi "Lainnya" di chart saja; daftarnya tetap lengkap.
- **Daftar kategori:** persen dan nominal, diurutkan dari yang terbesar.
- **Halaman rincian:** tap kategori untuk melihat:
  - grafik tren 6 bulan;
  - subkategori;
  - daftar transaksinya, yang bisa di-tap untuk edit.
- **Biaya transfer:** fee transfer muncul sebagai baris "Biaya transfer", sehingga total Statistik selalu sama dengan total di tab Transaksi.
  - Dicek di simulator: Nov 2026 Rp 98.199 dan Okt 2026 Rp 6.807.247, sama di kedua tab.

### Lainnya
- **Keamanan:**
  - Menyalakan "Kunci dengan Face ID" harus lolos Face ID dulu.
  - Pilihan "Kunci ulang setelah": Langsung / 1 menit / 5 menit / 15 menit.
- **Kunci aplikasi:**
  - Aplikasi terkunci saat dibuka dan saat kembali dari background setelah melewati batas waktu.
  - Layar kunci juga menutupi sheet yang sedang terbuka.
  - Di app switcher, isi aplikasi ditutup supaya data tidak terlihat.
- **Baris iCloud:** menampilkan "Aktif" atau "Tidak tersedia", plus penjelasan bila tidak aktif.

## Yang perlu kamu lakukan

1. **Aktifkan iCloud di Xcode, kalau mau sinkron antar perangkat.**
   - Entitlement sudah ditambahkan (`money-manager.entitlements`, container `iCloud.pakenanya.money-manager`). Build ke simulator berhasil.
   - Untuk iPhone asli, Xcode perlu membuat provisioning profile dengan kapabilitas iCloud. Caranya:
     1. Buka target **money-manager** → **Signing & Capabilities**.
     2. Pastikan **iCloud** (CloudKit, container di atas) dan **Background Modes → Remote notifications** tampil tanpa error. Kalau belum ada, klik **+ Capability** untuk menambahkannya.
   - iCloud/CloudKit **butuh Apple Developer Program berbayar**. Tanpa itu, aplikasi tetap berjalan normal dan data hanya tersimpan di iPhone.
2. **Install ulang ke iPhone kamu.** Setelah itu, cek baris iCloud di Lainnya. Kalau tertulis "Aktif", data mulai tersinkron.
3. **Saat pertama kali memasang di perangkat kedua:**
   - Aplikasi sempat membuat profil "Pribadi" kosong sebelum data iCloud datang.
   - Profil kosong yang namanya sama dengan profil berdata akan **dihapus otomatis** setelah sinkron.
   - Profil yang punya transaksi tidak pernah dihapus.

## Keputusan desain

- **Total Statistik = total Transaksi.** Fee transfer dihitung sebagai pengeluaran di kedua tab, dan di Statistik ditampilkan sebagai kategori "Biaya transfer".
- **Statistik per kategori induk.** Transaksi subkategori dihitung ke induknya. Rinciannya tampil di halaman detail.
- **Status iCloud tanpa `CKContainer`.** Status dibaca dari `ubiquityIdentityToken`, supaya aplikasi tidak crash kalau entitlement belum aktif.
- **Layar kunci di window terpisah** (level di atas alert), karena overlay SwiftUI biasa tidak bisa menutupi sheet yang sedang terbuka.
- **Pengaturan kunci tidak ikut sinkron.** Pengaturan ini disimpan per perangkat (UserDefaults), sesuai PRD.

## Masalah yang ditemukan saat verifikasi dan sudah diperbaiki

| Masalah | Perbaikan |
|---|---|
| Nama hari di Kalender tampil bahasa Inggris (Sun, Mon) bila bahasa iPhone Inggris | Selalu memakai `id_ID` + test baru |
| Nama bulan di grafik tren tampil bahasa Inggris (May, Oct) | Format bulan grafik memakai `id_ID` |
| Nama kategori di Statistik terpotong terlalu pendek ("Maka…", "Kehidu…") | Lebar emoji dibuat tetap dan nama boleh 2 baris |

## Keterbatasan yang diketahui

- **Sinkronisasi iCloud belum dicoba antar dua perangkat nyata.** Simulator tidak login iCloud, jadi baris iCloud baru dicek dalam kondisi "Tidak tersedia".
- **Emoji tampil sebagai kotak "?" di simulator ini.** Ini hanya masalah font di simulator, bukan bug aplikasi.
- **Tombol "Buka" di layar kunci memakai biru sistem,** bukan warna profil, karena layar kunci ada di window terpisah. Ini bisa diubah kalau mengganggu.

## File yang dibuat dan diubah

**Logika inti (`Packages/MoneyCore`)**
- Baru:
  - `Transactions/CalendarGrid.swift`: grid minggu per bulan dan nama hari.
  - `Statistics/StatsPeriod.swift`: periode Mingguan/Bulanan/Tahunan/Rentang.
  - `Statistics/StatisticsCalculator.swift`: porsi per kategori, subkategori, transaksi, dan tren.
  - `Security/AppLockPolicy.swift`: pengaturan dan aturan kapan aplikasi harus terkunci.
- Diubah:
  - `TransactionSummary.swift`: total per hari dan ringkasan 12 bulan.
  - `TransactionQueries.swift`: interval tahun.
  - `ProfileService.swift`: `removeEmptyDuplicates`.
  - `MoneySchema.swift`: iCloud `.automatic`.
- Test baru: `CalendarGridTests`, `StatsPeriodTests`, `StatisticsCalculatorTests`, `AppLockPolicyTests`, plus tambahan di `TransactionSummaryTests` dan `ProfileServiceTests`.

**Aplikasi (`money-manager/`)**
- Baru:
  - `Transactions/CalendarMonthView.swift`
  - `Transactions/MonthlyYearView.swift`
  - `Statistics/StatisticsView.swift`
  - `Statistics/CategoryStatsDetailView.swift`
  - `Security/AppLockController.swift`
  - `Security/LockScreenView.swift`
  - `More/SecuritySettingsView.swift`
- Diubah:
  - `TransactionListView.swift`: mode Kalender dan Bulanan, header bersama.
  - `RootView.swift`: tab Statistik.
  - `MoreView.swift`: Keamanan dan iCloud.
  - `money_managerApp.swift`: kunci aplikasi dan pembersihan profil ganda.
  - `DailySectionView.swift`: `TransactionRow` dibuat bisa dipakai ulang.

**Konfigurasi**
- `money-manager.entitlements`: iCloud CloudKit dan push.
- `money-manager-Info.plist`: background mode remote notification.
- `project.xcproj`: `CODE_SIGN_ENTITLEMENTS`, `INFOPLIST_FILE`, dan izin Face ID (`NSFaceIDUsageDescription`).

**Dokumen**
- Rencana 3 dan laporan ini.

## Daftar commit

```
f4edd08 fix: nama hari dan bulan selalu bahasa Indonesia, nama kategori statistik tidak terpotong
9c4b31d merge: tampilan kalender dan bulanan
208b898 feat(app): tampilan bulanan
4c90273 feat(app): tampilan kalender
e1bef05 merge: kunci face id dan status icloud
d28b851 feat(app): status icloud dan pembersihan profil ganda
b3bfe38 feat(app): kunci aplikasi dengan face id
127de9d feat(app): tab statistik
44fe179 chore: entitlement icloud, background push, dan izin face id
89cc735 feat(core): sinkron iCloud dan pembersihan profil ganda
4a56241 feat(core): aturan kunci aplikasi
145ab13 feat(core): perhitungan statistik per kategori
ed4c475 feat(core): grid kalender dan ringkasan per bulan
3ce5952 docs: rencana 3 kalender, statistik, face id, icloud
```

## Langkah berikutnya

- **Rencana 4:** Anggaran, transaksi berulang/cicilan, dan cari/filter/favorit (F7, F8, F9).
- **Rencana 2:** Import & Export xlsx/csv (F10, F11).
