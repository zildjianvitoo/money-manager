# PRD — Money Manager (iOS)

| | |
|---|---|
| **Versi** | 1.0 (MVP) |
| **Tanggal** | 1 November 2026 |
| **Pemilik** | Zildjian Vito |
| **Platform** | iPhone (iOS 26.0+), SwiftUI + SwiftData + CloudKit, desain Liquid Glass |
| **Status** | Draft — menunggu review |

---

## 1. Ringkasan

Aplikasi pencatat keuangan pribadi yang meniru kesederhanaan **Money Manager (Realbyte)**, dengan dua tambahan utama:

1. **Profil terpisah** (mis. *Pribadi* dan *Bisnis*). Setiap profil punya transaksi, aset, kategori, dan anggarannya sendiri. Cara pindah profil secepat ganti akun di Instagram/Threads.
2. **Import & export Excel/CSV** dari file export Money Manager, supaya seluruh history lama bisa dipindahkan tanpa hilang dan bisa dikeluarkan lagi kapan saja.

Fase pertama ini untuk dipakai sendiri, tanpa iklan, tanpa login, dan data disinkronkan lewat iCloud.

## 2. Latar Belakang & Masalah

- Money Manager versi gratis punya iklan, dan uang pribadi tidak bisa dipisahkan dari uang bisnis secara rapi. Trik yang biasa dipakai, yaitu memakai kategori atau aset khusus, membuat statistik dan total bulanan tercampur.
- History bertahun-tahun ada di Money Manager. Pindah ke aplikasi baru hanya masuk akal kalau history itu ikut pindah dengan utuh.

## 3. Tujuan & Metrik Sukses

| Tujuan | Metrik |
|---|---|
| History lama pindah utuh | 100% baris file export masuk (atau dilaporkan alasannya), dan total pengeluaran/pendapatan per bulan **sama persis** dengan Money Manager |
| Mencatat secepat Money Manager | Satu transaksi tercatat dalam **< 10 detik** sejak membuka aplikasi |
| Pindah profil instan | Ganti ke profil terakhir **1 gesture** (double-tap); ke profil mana pun **2 tap** |
| Data aman | Data tetap ada setelah ganti/reset iPhone (iCloud) dan bisa di-export kapan saja |

## 4. Di Luar Cakupan (Non-Goals) MVP

- Rilis ke App Store, onboarding untuk publik, paywall, analytics.
- Login, server/backend sendiri, dan berbagi data ke orang lain.
- Multi-mata uang (hanya Rupiah).
- iPad, Mac, Apple Watch.
- Sinkronisasi otomatis dengan bank atau e-wallet.

## 5. Pengguna

**Satu pengguna, yaitu pemilik aplikasi.** Ia mencatat pengeluaran harian (makan, transport, sewa), investasi rutin, dan keuangan usaha kecil secara terpisah. Ia terbiasa dengan alur Money Manager: buka aplikasi, tap **+**, ketik nominal di keypad kalkulator, pilih kategori dan aset, lalu simpan.

---

## 6. Fitur MVP

Prioritas: **P0** = wajib ada sebelum aplikasi dipakai harian. **P1** = wajib ada di MVP, boleh menyusul setelah P0 stabil.

### F1. Profil & Pindah Profil — P0

**Konsep:** profil adalah "ruang" data. Semua data di aplikasi (transaksi, aset, kategori, anggaran, transaksi berulang, favorit) selalu milik tepat satu profil. Pengaturan aplikasi (Face ID, tampilan) berlaku global.

**Kebutuhan:**
- Buat, ubah, dan hapus profil: nama, emoji/inisial sebagai avatar, dan warna aksen.
- Profil baru otomatis diisi kategori default (lihat F6) dan satu aset "Tunai". Opsi: *salin kategori dari profil lain*.
- Saat aplikasi pertama kali dibuka, profil **"Pribadi"** dibuat otomatis.
- Tab terakhir di **tab bar native iOS 26 (Liquid Glass)** menampilkan **avatar profil aktif** (emoji dalam lingkaran warna profil) dan berlabel nama profil, menggantikan ikon "Lainnya". Perilakunya seperti tab profil di Instagram.

**Gesture pada avatar profil di tab bar** (perilaku seperti IG/Threads):

| Gesture | Aksi |
|---|---|
| **Tap** | Buka tab profil/Lainnya (pengaturan, kelola profil, import/export) |
| **Double-tap** | Langsung pindah ke **profil terakhir** yang dipakai sebelum profil aktif, lalu kembali ke tab yang sedang dibuka sebelum double-tap |
| **Long-press** | Munculkan *profile switcher* (sheet) berisi daftar profil dan tombol "+ Tambah profil" |

**Kriteria penerimaan:**
- [ ] Setelah pindah profil, semua layar (Transaksi, Statistik, Aset, Anggaran) langsung menampilkan data profil baru tanpa perlu reload manual.
- [ ] Double-tap saat baru ada satu profil tidak melakukan apa-apa, cukup haptic ringan.
- [ ] Profil terakhir diingat walau aplikasi ditutup. Double-tap bolak-balik A → B → A → B konsisten.
- [ ] Setiap perpindahan profil memberi umpan balik: haptic, plus toast singkat "Beralih ke **Bisnis**".
- [ ] Nama dan warna aksen profil aktif selalu terlihat di header layar Transaksi, supaya transaksi tidak salah dicatat di profil yang keliru.
- [ ] Form tambah transaksi menampilkan nama profil tujuan.
- [ ] Menghapus profil membutuhkan konfirmasi dengan mengetik nama profil, lalu menghapus seluruh datanya. Profil terakhir yang tersisa tidak bisa dihapus.

### F2. Input Transaksi — P0

Tiga jenis transaksi: **Pendapatan**, **Pengeluaran**, **Transfer** (antar aset dalam profil yang sama).

**Field:**

| Field | Pendapatan/Pengeluaran | Transfer |
|---|---|---|
| Tanggal (+ jam) | wajib, default sekarang | wajib |
| Total | wajib, > 0 | wajib, > 0 |
| Kategori (+ subkategori) | wajib | — |
| Aset | wajib | **Dari** dan **Ke** (wajib, harus berbeda) |
| Biaya transfer | — | opsional, dicatat sebagai pengeluaran di aset asal |
| Catatan | opsional (judul singkat, mis. "makan siang") | opsional |
| Deskripsi | opsional (teks panjang) | opsional |
| Berulang/cicil | opsional (lihat F8) | opsional |

**Kebutuhan:**
- **Keypad kalkulator** seperti di Money Manager: angka, `+ − × ÷ =`, koma, hapus, dan tombol **Ya**. Ekspresi dihitung sebelum disimpan.
- Alur cepat: setelah Total diisi dan **Ya** ditekan, fokus pindah ke Kategori, lalu Aset. Pilihan kategori dan aset tampil sebagai grid atau daftar di sheet bawah, tanpa pindah halaman.
- Tombol **Simpan** dan **Simpan & Lanjut** (form dikosongkan, tanggal tetap).
- **Edit** dengan tap transaksi di daftar. **Hapus** dengan swipe atau dari halaman edit. **Duplikat** dari halaman edit (salinan memakai tanggal hari ini).
- Saran Catatan: saat mengetik, muncul autocomplete dari catatan sebelumnya di kategori yang sama (mis. "makan malam").

**Kriteria penerimaan:**
- [ ] Nominal disimpan sebagai `Decimal`, tidak pernah `Double`.
- [ ] Ekspresi tidak valid (mis. `5÷0`) menampilkan error dan tidak bisa disimpan.
- [ ] Transfer tidak memengaruhi total Pendapatan/Pengeluaran, hanya saldo aset.
- [ ] Format angka Indonesia: `Rp 1.280.402`. Desimal hanya tampil kalau nilainya bukan bulat.

### F3. Daftar Transaksi — P0

Tab **Transaksi** dengan navigasi bulan (`‹ Okt 2026 ›`) dan ringkasan **Pendapatan / Pengeluaran / Total** bulan berjalan.

Sub-tab:
- **Harian:** dikelompokkan per tanggal (terbaru di atas). Header grup berisi tanggal, hari, total pendapatan, dan total pengeluaran hari itu. Setiap baris menampilkan ikon + kategori, catatan, aset, dan nominal (biru untuk pendapatan, merah untuk pengeluaran, abu-abu untuk transfer).
- **Kalender:** grid bulan. Setiap tanggal menampilkan total pendapatan dan pengeluaran. Tap tanggal untuk melihat daftar transaksi hari itu.
- **Bulanan:** daftar 12 bulan dalam satu tahun dengan pendapatan, pengeluaran, dan total. Tap bulan untuk membuka Harian bulan itu.

Tombol **+** mengambang untuk menambah transaksi. Tanggal default mengikuti tanggal yang sedang dilihat di Kalender.

**Kriteria penerimaan:**
- [ ] Scroll tetap lancar dengan 10.000+ transaksi (hasil import history bertahun-tahun).
- [ ] Swipe kiri/kanan pada area daftar berpindah bulan.

### F4. Statistik — P0

- Pilih periode: **Mingguan / Bulanan / Tahunan / Rentang tanggal**, dengan navigasi `‹ ›`.
- Toggle **Pendapatan / Pengeluaran**, lengkap dengan totalnya.
- **Pie/donut chart** per kategori (Swift Charts), plus daftar kategori dengan persentase dan nominal, diurutkan dari yang terbesar.
- Tap kategori untuk membuka rincian per subkategori dan daftar transaksinya, plus grafik batang tren 6 bulan terakhir untuk kategori itu.

**Kriteria penerimaan:**
- [ ] Transfer tidak masuk statistik.
- [ ] Total di Statistik sama persis dengan total di tab Transaksi untuk periode yang sama.

### F5. Aset — P0

- Aset dikelompokkan per **grup**: Tunai, Bank, E-Wallet, Kartu Kredit, Investasi, Lainnya.
- Field aset: nama, grup, **saldo awal**, *masuk total kekayaan* (ya/tidak), dan arsip.
- Layar Aset menampilkan **Aset** (jumlah saldo positif), **Liabilitas** (jumlah saldo negatif, mis. kartu kredit), dan **Total**.
- Saldo aset = saldo awal + pendapatan − pengeluaran + transfer masuk − transfer keluar.
- Tap aset untuk melihat riwayat transaksinya per bulan beserta saldo berjalan.
- **Sesuaikan saldo**: masukkan saldo sebenarnya, lalu aplikasi membuat transaksi berjenis khusus **Penyesuaian** untuk menutup selisihnya. Penyesuaian hanya memengaruhi saldo aset dan **tidak** dihitung di total Pendapatan/Pengeluaran maupun Statistik, supaya statistik tidak terdistorsi.
- Aset yang diarsipkan tidak muncul di pilihan input, tapi transaksinya tetap ada.

### F6. Kelola Kategori — P0

- Kategori terpisah untuk Pendapatan dan Pengeluaran. Setiap kategori bisa punya **subkategori** (satu level).
- Tambah, ubah nama, emoji/ikon, urutkan (drag), dan sembunyikan.
- Menghapus kategori yang sudah dipakai mewajibkan memilih kategori pengganti, lalu semua transaksinya dipindahkan ke sana.
- **Kategori default Pengeluaran:** Makanan, Transportasi, Biaya Sewa Tempat Tinggal, Kebutuhan Rumah, Kehidupan Sosial, Pakaian, Kecantikan, Kesehatan, Pendidikan, Hiburan, Invest, Lainnya.
- **Kategori default Pendapatan:** Gaji, Bonus, Usaha, Hasil Investasi, Lainnya.

### F7. Anggaran — P1

- Batas bulanan per kategori pengeluaran, dan opsional satu batas total.
- Tab **Anggaran** di layar Statistik (seperti Money Manager) menampilkan progress bar per kategori: terpakai, sisa, dan persentase. Warnanya hijau (< 80%), kuning (80–100%), dan merah (> 100%).
- Anggaran berlaku setiap bulan sampai diubah. Perubahan hanya berlaku mulai bulan yang dipilih, sehingga bulan sebelumnya tetap memakai nilai lama.

### F8. Transaksi Berulang & Cicilan — P1

Diakses lewat tombol **Berulang/cicil** di form transaksi.

- **Berulang:** frekuensi harian, mingguan, bulanan, atau tahunan; tanggal mulai; berakhir (tidak pernah / pada tanggal tertentu). Contoh: sewa rusun setiap tanggal 30, invest bulanan.
- **Cicilan:** jumlah kali (mis. 12x). Nominal per cicilan = total ÷ jumlah, dengan sisa pembulatan dibebankan ke cicilan terakhir. Catatan otomatis diberi akhiran "(3/12)".
- Transaksi dibuat otomatis saat aplikasi dibuka atau kembali ke foreground, untuk semua jadwal yang jatuh tempo sampai hari ini, termasuk yang terlewat.
- Daftar "Transaksi Berulang" di tab Lainnya untuk mengubah, menjeda, atau menghapus aturan. Menghapus aturan tidak menghapus transaksi yang sudah terbuat.

**Kriteria penerimaan:**
- [ ] Setiap kemunculan punya kunci unik (`ruleID + tanggal jadwal`). Kalau sync iCloud membawa kemunculan yang sama dari perangkat lain, duplikatnya dibersihkan.
- [ ] Jadwal "tanggal 31" di bulan yang lebih pendek jatuh di hari terakhir bulan itu.

### F9. Cari, Filter & Favorit — P1

- **Cari** (ikon kaca pembesar): teks bebas di catatan dan deskripsi, dalam profil aktif dan semua periode. Hasil dikelompokkan per tanggal dan menampilkan total hasil pencarian.
- **Filter** (ikon slider): jenis transaksi, kategori, aset, dan rentang nominal. Filter berlaku di tab Transaksi dan Statistik, dan ditandai dengan badge selama aktif.
- **Favorit** (ikon bintang): simpan transaksi sebagai template (jenis, kategori, aset, catatan, nominal opsional). Dari form transaksi, tap bintang lalu pilih favorit untuk mengisi form otomatis. Favorit juga bisa ditambahkan dari halaman edit transaksi lewat "Simpan sebagai favorit".

### F10. Import dari Money Manager (xlsx/csv) — P0

**Alur:**
1. Lainnya → **Import** → pilih file dari Files (`.xlsx` / `.csv`). Pilih **profil tujuan** (default: profil aktif).
2. **Pratinjau:** jumlah baris, rentang tanggal, total pendapatan/pengeluaran per bulan, dan baris yang gagal dibaca beserta alasannya.
3. **Pemetaan:** daftar kategori, subkategori, dan aset dari file. Setiap item bisa dipetakan ke yang sudah ada atau dibuat baru (default). Grup aset dan saldo awal bisa diatur di langkah ini.
4. **Deteksi duplikat:** baris yang identik dengan transaksi yang sudah ada (tanggal, nominal, jenis, aset, kategori, catatan) ditandai, dan default-nya dilewati.
5. **Import.** Semua baris disimpan sebagai satu **batch import** dalam satu operasi simpan, lalu tampil ringkasan "1.234 transaksi diimpor, 3 dilewati".
6. **Undo:** di Lainnya → Riwayat Import, setiap batch bisa dibatalkan (semua transaksinya dihapus, kategori dan aset yang dibuat batch itu ikut dihapus kalau tidak dipakai lagi).

**Format file (ASUMSI — divalidasi dengan file contoh asli):**
Kolom export Money Manager diperkirakan: `Period` (tanggal+jam), `Accounts`, `Category`, `Subcategory`, `Note`, `IDR`/`Amount`, `Income/Expense` (nilainya `Income`, `Expense`, `Transfer-Out`, `Transfer-In`), `Description`, `Currency`.
- Pencocokan kolom berdasarkan nama header, tidak bergantung pada urutan. Kalau header tidak dikenali, pengguna memetakan kolom secara manual.
- **Transfer:** pasangan `Transfer-Out` dan `Transfer-In` dengan waktu dan nominal yang sama digabung menjadi satu transaksi Transfer. Pasangan yang tidak lengkap dilaporkan.
- Format angka: menerima `19000`, `19.000`, `19.000,00`, dan `19,000.00`. Format tanggal mengikuti file dan dideteksi otomatis.
- File besar (≥ 20.000 baris) diproses di background dengan progress bar, tanpa membekukan UI.

**Kriteria penerimaan:**
- [ ] Setelah import file asli milik pemilik, total pendapatan dan pengeluaran **setiap bulan** sama persis dengan yang tampil di Money Manager.
- [ ] Import file yang sama dua kali tanpa perubahan tidak menambah transaksi apa pun.
- [ ] Import yang gagal di tengah jalan tidak meninggalkan data setengah jadi.

### F11. Export (xlsx/csv) — P1

- Lainnya → **Export** → pilih profil, rentang tanggal (default: semua), dan format (`.xlsx` / `.csv`). File dibagikan lewat share sheet (simpan ke Files, AirDrop, dll).
- Kolom export **sama dengan format Money Manager**, sehingga hasil export bisa di-import lagi ke aplikasi ini (round-trip) dan dibuka di Excel/Numbers.
- CSV memakai UTF-8 dengan BOM agar Excel membaca karakter dan emoji dengan benar.

**Kriteria penerimaan:**
- [ ] Export lalu import ke profil kosong menghasilkan data yang identik: jumlah transaksi dan total per bulan sama.

### F12. Kunci Aplikasi (Face ID / Passcode) — P0

- Toggle di Lainnya. Saat aktif, aplikasi meminta Face ID (fallback: passcode perangkat) saat dibuka dan saat kembali dari background lebih dari *N* menit (default 1 menit, bisa diatur).
- Saat aplikasi ada di app switcher, kontennya diburamkan.

### F13. Sinkronisasi iCloud — P0

- Data disimpan lewat SwiftData dengan CloudKit private database. Tanpa login tambahan, cukup Apple ID di perangkat.
- Status sync tampil di Lainnya (aktif / iCloud tidak tersedia).
- Kalau iCloud nonaktif, aplikasi tetap berfungsi penuh secara lokal.

---

## 7. Pedoman UI (modern, clean, sesuai HIG)

- **Pakai komponen sistem iOS 26** dan biarkan sistem yang memberi efek Liquid Glass:
  - `TabView` native, `NavigationStack` dengan large title di layar utama.
  - `List` inset grouped untuk form dan pengaturan.
  - Sheet dengan detent, `Menu`, `confirmationDialog`, swipe actions, dan `ContentUnavailableView` untuk state kosong.
- **Jangan tiru efek glass sendiri.** `.glassEffect` / `.buttonStyle(.glass)` hanya untuk elemen kustom yang mengambang, seperti tombol **+**.
- **Warna:**
  - Pakai warna semantic (`.primary`, `.secondary`, background sistem), supaya otomatis menyesuaikan light dan dark mode.
  - Satu warna aksen, yaitu **warna profil aktif**, yang dipakai sebagai `tint`. Dengan begitu, beda profil langsung terlihat.
  - Pendapatan `.blue`, pengeluaran `.red`, transfer `.secondary`.
- **Tipografi:** pakai text style sistem (Dynamic Type sampai ukuran aksesibilitas terbesar). Nominal memakai `.monospacedDigit()` supaya kolom angka rata.
- **Ikon:** SF Symbols. Tab: Transaksi `list.bullet.rectangle.portrait`, Statistik `chart.pie`, Aset `building.columns`, profil = avatar.
- **Pola layar:**
  - Form transaksi tampil sebagai sheet dengan **Batal** di kiri atas dan **Simpan** di kanan atas, plus **Simpan & Lanjut** di bawah.
  - Konfirmasi hapus memakai `confirmationDialog` dengan tombol merah.
  - Kembali ke layar sebelumnya selalu bisa dengan swipe dari tepi kiri.
- **Clean:**
  - Tanpa iklan dan tanpa garis pemisah berlebihan; hierarki dibangun lewat spasi dan ukuran teks.
  - Maksimal satu aksi utama per layar.
  - Haptic hanya untuk simpan, ganti profil, dan hapus.
- **Aksesibilitas:**
  - Target sentuh minimal 44×44 pt.
  - Label VoiceOver untuk semua tombol ikon.
  - Aksi VoiceOver "Ganti profil" dan "Profil terakhir" pada tab profil, karena gesture long-press dan double-tap tidak terjangkau VoiceOver.
  - Menghormati Reduce Motion.
- **Dicek di:** iPhone 16e (layar kecil) dan iPhone 17 Pro Max, light dan dark, ukuran teks aksesibilitas terbesar, di iOS 26.3.

## 8. Navigasi & Layar

```
Tab Bar
├── Transaksi    — Harian | Kalender | Bulanan, Cari, Filter, Favorit, tombol +
├── Statistik    — Statistik | Anggaran
├── Aset         — daftar per grup, detail aset, sesuaikan saldo
└── [Avatar profil]  tap: Lainnya | double-tap: profil terakhir | long-press: switcher   (tab bar native Liquid Glass)
        Lainnya
        ├── Profil (kelola, tambah, hapus)
        ├── Kategori
        ├── Transaksi Berulang
        ├── Import / Riwayat Import / Export
        ├── Keamanan (Face ID)
        └── iCloud & Tentang
```

Layar modal: Form transaksi (sheet penuh), pemilih kategori/aset (sheet bawah), profile switcher (sheet bawah, seperti IG), dan wizard import (navigation stack dalam sheet).

## 9. Model Data (SwiftData)

Semua model bisnis punya `profileID: UUID` (scalar, supaya `#Predicate` sederhana dan cepat). Batasan CloudKit: semua properti punya nilai default atau optional, relasi optional, dan **tidak ada** `@Attribute(.unique)`. Keunikan dijaga di level aplikasi.

| Model | Field utama |
|---|---|
| `Profile` | `id`, `name`, `emoji`, `colorHex`, `sortOrder`, `createdAt` |
| `AssetAccount` | `id`, `profileID`, `name`, `group` (enum), `initialBalance: Decimal`, `includeInTotal`, `isArchived`, `sortOrder` |
| `MoneyCategory` | `id`, `profileID`, `name`, `emoji`, `kind` (income/expense), `parent: Category?`, `isHidden`, `isSystem`, `sortOrder` |
| `MoneyTransaction` | `id`, `profileID`, `type` (income/expense/transfer/adjustment), `amount: Decimal` (disimpan sebagai `amountMinor: Int64` dalam sen agar aman untuk CloudKit), `fee: Decimal?`, `date`, `category?`, `asset?`, `toAsset?`, `note`, `detail`, `recurringRuleID?`, `occurrenceKey?`, `importBatchID?`, `createdAt`, `updatedAt` |
| `Budget` | `id`, `profileID`, `category?` (nil = total), `amount: Decimal`, `effectiveFrom` (bulan) |
| `RecurringRule` | `id`, `profileID`, template field transaksi, `frequency`, `startDate`, `endDate?`, `installmentCount?`, `lastGeneratedDate?`, `isPaused` |
| `FavoriteTemplate` | `id`, `profileID`, template field transaksi, `sortOrder` |
| `ImportBatch` | `id`, `profileID`, `fileName`, `importedAt`, `rowCount`, `createdCategoryIDs`, `createdAssetIDs` |

**Disimpan di `UserDefaults` (per perangkat, tidak di-sync):** `activeProfileID`, `previousProfileID` (untuk double-tap), dan pengaturan kunci aplikasi.

Saldo aset dan total **tidak disimpan**, melainkan dihitung dari transaksi. Kalau performa dengan 10.000+ transaksi bermasalah, baru ditambah cache.

## 10. Arsitektur Teknis

- **UI:** SwiftUI, iOS 26.0+ (deployment target proyek diturunkan dari 27.2 ke 26.0), iPhone saja. Ikuti Pedoman UI (bagian 7).
- **Tab bar native** (`TabView` iOS 26, otomatis Liquid Glass).
  - `TabView` tidak menyediakan double-tap dan long-press per item, jadi keduanya dipasang lewat **jembatan UIKit kecil** (`TabBarGestureBridge`) yang menempelkan `UITapGestureRecognizer` (2 tap) dan `UILongPressGestureRecognizer` ke `UITabBar` milik `TabView`. Recognizer memakai `cancelsTouchesInView = false`, sehingga tap biasa tetap ditangani sistem tanpa delay. Cara ini sama dengan yang dipakai aplikasi UIKit seperti Instagram.
  - **Risiko:** update iOS bisa mengubah struktur internal tab bar. Implementasi diawali spike untuk memastikannya di iOS 26.3 dan 27.
  - **Fallback kalau jembatan gagal:** gesture dimatikan secara diam-diam, dan switcher tetap bisa dibuka dari halaman Lainnya dan lewat aksi VoiceOver. Aplikasi tidak boleh crash.
- **State profil:** `ProfileStore` (`@Observable`) di environment menyimpan profil aktif dan sebelumnya. Semua query menerima `profileID` sebagai parameter. Ganti profil berarti mengganti ID, lalu view yang bergantung otomatis query ulang.
- **Lapisan:**
  - `Models/` untuk model SwiftData.
  - `Services/` untuk logika tanpa UI yang bisa diuji: `AmountParser` (kalkulator), `BalanceCalculator`, `RecurringEngine`, `MoneyManagerImporter`, `Exporter`, `DuplicateDetector`.
  - `Features/<Fitur>/` untuk view per fitur.
- **Dependensi (SPM):** [CoreXLSX](https://github.com/CoreOffice/CoreXLSX) untuk membaca xlsx. Untuk menulis xlsx, library penulis xlsx dievaluasi saat implementasi; fallback-nya menulis xlsx minimal sendiri (zip + XML).
- **Chart:** Swift Charts (`SectorMark` untuk pie, `BarMark` untuk tren).
- **Keamanan:** LocalAuthentication untuk Face ID.

## 11. Edge Case & Penanganan Error

| Kasus | Perilaku |
|---|---|
| Hapus aset/kategori yang dipakai transaksi | Wajib pilih pengganti, atau arsipkan saja |
| Transaksi tanpa kategori atau aset (mis. setelah sync yang tidak lengkap) | Tampil sebagai "Tanpa kategori" dan tidak membuat aplikasi crash |
| iCloud penuh atau nonaktif | Simpan lokal, tampilkan status di Lainnya |
| Konflik sync | Last-write-wins (perilaku bawaan CloudKit) |
| Baris import rusak | Dilewati, dicantumkan di laporan beserta nomor baris dan alasannya |
| Nominal 0 atau negatif di form | Tombol simpan nonaktif |
| Zona waktu | Tanggal disimpan apa adanya dan dikelompokkan menurut kalender lokal perangkat |

## 12. Pengujian

- **Unit test (wajib, dikerjakan TDD)** untuk `AmountParser`, `BalanceCalculator`, `RecurringEngine` (termasuk tanggal 31 dan cicilan dengan sisa pembulatan), `MoneyManagerImporter` (angka, tanggal, pasangan transfer, header tak dikenal), `DuplicateDetector`, dan round-trip `Exporter` → `Importer`.
- **Test isolasi profil:** data profil A tidak pernah muncul di query profil B, di semua layar dan service.
- **Fixture:** file export Money Manager asli (anonim bila perlu) disimpan di target test sebagai sumber kebenaran.
- **Uji manual:** import seluruh history asli lalu cocokkan total setiap bulan dengan Money Manager. Uji double-tap dan long-press di perangkat asli.

## 13. Roadmap Setelah MVP (Fase 2)

- Pengingat harian (notifikasi jam tertentu).
- Widget & Shortcut / quick add dari Lock Screen.
- Tampilan Ringkasan & Deskripsi (seperti Money Manager).
- Transfer antar profil (mis. prive dari Bisnis ke Pribadi).
- Tanggal mulai bulan custom (siklus gajian).
- Foto struk pada transaksi.
- Multi-mata uang.
- Persiapan rilis App Store (onboarding, kebijakan privasi).

## 14. Urutan Pengerjaan

1. **Fondasi:** model data, `ProfileStore`, custom tab bar dengan gesture profil, kategori default.
2. **Inti pencatatan:** form transaksi + keypad kalkulator, daftar Harian, edit/hapus/duplikat.
3. **Aset & kategori:** layar Aset, saldo, kelola kategori.
4. **Import:** importer + wizard + undo, divalidasi dengan file asli. *Milestone: aplikasi siap dipakai harian.*
5. **Kalender, Bulanan, Statistik.**
6. **Face ID + iCloud.**
7. **P1:** Anggaran, Berulang/Cicilan, Cari/Filter/Favorit, Export.

## 15. Pertanyaan Terbuka

1. **Format file export Money Manager.** Menunggu file contoh untuk memastikan nama kolom, format tanggal/angka, dan representasi transfer (bagian F10).
2. Apakah history lama perlu dipecah ke profil Pribadi dan Bisnis saat import? Contohnya berdasarkan aset atau kategori tertentu. Asumsi MVP: satu file diimpor ke satu profil.
