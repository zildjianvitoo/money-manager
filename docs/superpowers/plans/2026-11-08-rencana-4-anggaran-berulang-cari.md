# Rencana 4 — Anggaran, Transaksi Berulang/Cicilan, Cari/Filter/Favorit

**Spec:** [`docs/PRD-money-manager.md`](../../PRD-money-manager.md) F7, F8, F9 (semua P1). Konvensi Rencana 1–3 tetap berlaku: logika di `Packages/MoneyCore` dengan TDD, app hanya view; build dan uji di simulator memakai skill `ios-simulator-skill` (`build_and_test.py --simulator "iPhone 17 Pro" --run`, `navigator.py`, `gesture.py`).

Ketiga fitur saling bebas, jadi dikerjakan berurutan sebagai tiga bagian terpisah, masing-masing satu branch/PR. Urutan: 4a → 4b → 4c (anggaran paling kecil dan memakai data yang sudah ada).

## 4a. Anggaran (F7)
- **Model** `Budget` (`profileID`, `category?` nil = total, `amountMinor`, `effectiveFrom` = awal bulan). Masuk `MoneySchema`, hapus bersama profil.
- **Core** `BudgetService`: atur anggaran mulai bulan X (tidak mengubah bulan sebelumnya), ambil anggaran berlaku untuk bulan Y, hitung terpakai/sisa/persen per kategori induk memakai aturan `StatisticsCalculator` (pengeluaran + fee transfer, subkategori dihitung ke induk), tingkat warna (<80% hijau, 80–100% kuning, >100% merah).
- **UI** tab "Anggaran" di layar Statistik: progress bar per kategori, form atur batas, batas total opsional.
- **Test:** perubahan berlaku mulai bulan dipilih, bulan lama tetap; total anggaran vs total pengeluaran sama dengan tab Transaksi; batas warna 79,9/80/100/100,1%.

## 4b. Transaksi Berulang & Cicilan (F8)
- **Model** `RecurringRule` (template transaksi, `frequency`, `startDate`, `endDate?`, `installmentCount?`, `lastGeneratedDate?`, `isPaused`). `MoneyTransaction.recurringRuleID` dan `occurrenceKey` sudah ada.
- **Core** `RecurringEngine`: hitung kemunculan jatuh tempo sampai hari ini (termasuk yang terlewat), tanggal 31 jatuh di hari terakhir bulan pendek, cicilan = total ÷ n dengan sisa pembulatan di cicilan terakhir dan catatan berakhiran "(3/12)", kunci unik `ruleID + tanggal jadwal`, pembersihan kemunculan ganda setelah sinkron iCloud.
- **UI** tombol "Berulang/cicil" di form transaksi; daftar Transaksi Berulang di Lainnya (ubah, jeda, hapus; menghapus aturan tidak menghapus transaksi). Pembuatan otomatis saat app dibuka/foreground.
- **Test:** 31 Jan→28/29 Feb, tahun kabisat, cicilan sisa pembulatan, idempoten saat dijalankan dua kali, jeda, aturan berakhir.

## 4c. Cari, Filter & Favorit (F9)
- **Model** `FavoriteTemplate` (jenis, kategori, aset, catatan, nominal opsional, `sortOrder`).
- **Core** `TransactionFilter` (jenis, kategori, aset, rentang nominal) dan pencarian teks di catatan + deskripsi, semua periode, per profil; dipakai tab Transaksi dan Statistik.
- **UI** ikon cari dan filter (badge saat aktif) di tab Transaksi; bintang di form transaksi untuk memilih favorit; "Simpan sebagai favorit" di edit transaksi.
- **Test:** filter tidak bocor antar profil, kombinasi filter, total hasil pencarian, template mengisi form.

## Review Focus
1. Total Anggaran/Statistik/Transaksi konsisten untuk bulan yang sama.
2. Transaksi berulang tidak pernah terbuat dua kali (app dibuka berkali-kali, dua perangkat).
3. Data tidak bocor antar profil di model baru.
