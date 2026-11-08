# Laporan Rencana 4 — Cari, Filter & Favorit (F9)

**Tanggal:** 8 November 2026
**Branch:** `feat/cari-filter-favorit` (dari `feat/rencana-2`)
**Rencana:** [`docs/superpowers/plans/2026-11-08-rencana-4-cari-filter-favorit.md`](../superpowers/plans/2026-11-08-rencana-4-cari-filter-favorit.md)

## Ringkasan

- **Dihapus dari lingkup (keputusan pemilik):** Anggaran (F7) dan Transaksi Berulang/Cicilan (F8). Dihapus juga dari PRD (fitur, model `Budget`/`RecurringRule`, tab Anggaran, menu Transaksi Berulang) dan baris "Segera hadir" di Lainnya.
- **F9 selesai:** cari, filter, dan favorit.
- Unit test: **162 lulus** (sebelumnya 147). Build app: `** BUILD SUCCEEDED **`. Dicoba di simulator iPhone 17 Pro (iOS 26.3) dengan skill `ios-simulator-skill`.

## Yang bisa dicoba

- **Cari** (ikon kaca pembesar di tab Transaksi): kata bebas di catatan dan deskripsi, semua periode, profil aktif. Semua kata harus cocok, tanpa beda huruf besar/kecil dan aksen. Hasil dikelompokkan per tanggal (nama hari/bulan bahasa Indonesia) dengan jumlah hasil dan total pendapatan/pengeluaran. Tap hasil untuk mengedit.
- **Filter** (ikon slider di tab Transaksi dan Statistik): jenis, kategori (induk ikut menyertakan subkategori), aset (asal atau tujuan), rentang nominal. Lencana menunjukkan jumlah kelompok filter aktif. Filter yang sama berlaku di Harian/Kalender/Bulanan, Statistik, dan rincian kategori; direset saat ganti profil. Bila filter menyembunyikan semuanya, layar kosong menawarkan "Hapus filter".
- **Favorit:** di form transaksi baru, ikon bintang membuka daftar favorit (tap untuk mengisi form, geser untuk hapus). Di form edit ada "Simpan sebagai favorit" (nama bisa diubah, simpan dengan atau tanpa nominal). Memakai favorit tidak mengubah tanggal.

## Hasil verifikasi

- Pencarian "puln" di profil Bisnis: **54 hasil, total pendapatan Rp 2.401.000, pengeluaran Rp 0**. Dicocokkan dengan hitungan terpisah dari file backup yang sama (54, 2.401.000, 0).
- Filter Pengeluaran di Nov 2026: tab Transaksi dan Statistik sama-sama menunjukkan Pendapatan Rp 0, Pengeluaran Rp 45.500; lencana "1" dan "Filter, 1 aktif" tampil.
- Favorit dibuat dari transaksi "email hotmail" (Rp 10.500), lalu dipakai di form baru: total, kategori Shopping, dan aset Ticket Business terisi.

## Belum dicoba / perlu dicek

- **Filter kategori, aset, dan rentang nominal di UI** belum dicoba di simulator; logikanya dites unit (kombinasi AND, induk+sub, transfer, batas inklusif).
- **Hapus favorit lewat geser** dan **favorit transfer** belum dicoba di UI.
- **Pencarian di 10.000+ transaksi:** semua transaksi profil dimuat lalu disaring di memori. Belum diukur.
- **Statistik:** bila filter aktif, rincian kategori ikut terfilter, jadi total bisa lebih kecil dari yang diharapkan kalau lupa filter aktif (lencana tampil di header).
- Kolom `recurringRuleID` dan `occurrenceKey` di `MoneyTransaction` masih ada di kode walau fitur Berulang dihapus; dibiarkan agar tidak mengubah skema yang sudah tersinkron.

## Langkah berikutnya

Sisa dari daftar: aktivasi iCloud di Xcode dan uji antar perangkat, tes gesture tab bar di perangkat asli, lalu Fase 2 di PRD.
