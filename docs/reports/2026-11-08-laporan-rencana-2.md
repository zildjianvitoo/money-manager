# Laporan Rencana 2 — Import & Export

**Tanggal:** 8 November 2026
**Branch:** `feat/rencana-2` (dari `fix/profil-bisnis-pendapatan`)
**Rencana:** [`docs/superpowers/plans/2026-11-08-rencana-2-import-export.md`](../superpowers/plans/2026-11-08-rencana-2-import-export.md)

## Ringkasan

Import dari backup JSON Money Manager dan CSV, export CSV, riwayat import, dan undo sudah jalan.

- Unit test: **147 lulus** (sebelumnya 127).
- Build app: `** BUILD SUCCEEDED **`.
- Dicoba di simulator iPhone 17 Pro dengan file backup asli (78 transaksi): pratinjau, import, dan Riwayat Import berfungsi.

## Keputusan yang menyimpang dari PRD

| PRD | Dikerjakan | Alasan |
|---|---|---|
| Import xlsx/csv | **JSON backup + CSV** | File asli ternyata JSON backup (`appName: "Money Manager"`, versi 2.0). Tidak ada contoh xlsx. xlsx ditunda. |
| Export xlsx/csv | **CSV** (UTF-8 BOM) | Mengikuti keputusan di atas. |
| Pemetaan manual kategori/aset | **Otomatis berdasarkan nama** | Nama cocok (tanpa beda huruf besar/kecil) dipakai ulang, sisanya dibuat baru. Pratinjau menampilkan daftar yang akan dibuat. Pemetaan manual belum ada. |
| `.mmbak` | Tidak didukung | File SQLite; JSON sudah memuat semua data. |

## Cara kerja

- **Format JSON:** `transactionType` 0 = pendapatan, 1 = pengeluaran. Subkategori dikenali dari `parentCategoryId`. Tanggal tanpa zona waktu dibaca sebagai waktu lokal.
- **Saldo awal aset baru** = saldo sekarang di file dikurangi pengaruh transaksi yang diimpor, sehingga saldo di aplikasi sama dengan saldo di file.
- **Duplikat:** baris dengan tanggal, nominal, jenis, aset, kategori, dan catatan yang sama dengan transaksi yang sudah ada dilewati (bisa dimatikan). Dua baris kembar yang sah di dalam satu file tetap masuk pada import pertama.
- **Atomik:** semua baris disimpan sekali; bila gagal, `rollback` dan tidak ada data setengah jadi.
- **Undo:** menghapus transaksi batch, lalu kategori/aset buatan batch itu bila tidak dipakai lagi. Menghapus profil ikut menghapus riwayat importnya.
- **CSV:** header dikenali lewat nama (ada beberapa alias), angka `19000`, `19.000`, `19.000,50`, `19,000.50`, dan pasangan `Transfer-Out`/`Transfer-In` digabung. Export tidak menyertakan penyesuaian saldo.

## Hasil verifikasi

- File backup asli: 78 baris terbaca, 0 gagal. Total per bulan sama dengan hitungan terpisah dari JSON yang sama:

| Bulan | Pendapatan | Pengeluaran |
|---|---|---|
| Sep 2026 | 3.000.000 | 137.000 |
| Okt 2026 | 9.518.000 | 835.000 |
| Nov 2026 | 868.000 | 45.500 |

- Setelah import, pratinjau menyatakan 78 transaksi sudah ada, jadi import ulang file yang sama tidak menambah apa pun (dites juga di unit test).
- Round-trip export → import ke profil kosong: jumlah transaksi dan total per bulan sama, termasuk catatan dengan koma, kutip, dan baris baru.

- Dicek ulang di simulator memakai skill ios-simulator-skill: undo lewat UI (geser kiri → Batalkan → konfirmasi) mengosongkan profil, import ulang memasukkan 78 transaksi lagi, dan Export membuka share sheet berisi `Duitku-Bisnis-2026-11-08.csv` (6 KB).

## Belum dicoba / perlu dicek

- **File besar (≥ 20.000 baris)** belum diukur. Parsing berjalan di background, tetapi pratinjau dan penyimpanan masih di main thread.
- **Transfer di format JSON** belum pernah ada di data nyata, jadi dilaporkan sebagai baris gagal.
- **Import ke profil Pribadi:** PRD menanyakan apakah history perlu dipecah per profil; saat ini satu file masuk ke satu profil.

## Langkah berikutnya

- **Rencana 4:** Anggaran, transaksi berulang/cicilan, cari/filter/favorit (F7, F8, F9).
