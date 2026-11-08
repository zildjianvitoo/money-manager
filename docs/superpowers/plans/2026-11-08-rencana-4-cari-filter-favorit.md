# Rencana 4 — Cari, Filter & Favorit (F9)

**Keputusan pemilik, 8 Nov 2026:** Anggaran (F7) dan Transaksi Berulang/Cicilan (F8) **dihapus** dari lingkup dan dari PRD. Rencana 4 hanya F9.

**Spec:** [`docs/PRD-money-manager.md`](../../PRD-money-manager.md) F9. Konvensi sebelumnya berlaku: logika di `Packages/MoneyCore` dengan TDD; build dan uji di simulator memakai skill `ios-simulator-skill`.

## Core
- `TransactionFilter` (jenis, kategori induk/sub, aset asal/tujuan, rentang nominal inklusif; kriteria digabung AND; `activeCount` untuk badge).
- `TransactionSearch.search` — kata bebas di catatan dan deskripsi, tanpa beda huruf besar/kecil dan aksen, semua kata harus cocok.
- `FavoriteTemplate` (id kategori/aset disimpan sebagai id, bukan relasi) + `FavoriteService` (buat dari draft dengan/tanpa nominal, hapus, `apply` ke draft; id yang sudah dihapus dikosongkan; terisolasi per profil). Masuk `MoneySchema`, ikut terhapus bersama profil.

## UI
- Ikon cari dan filter di tab Transaksi. Filter (badge jumlah kriteria aktif) berlaku di tab Transaksi dan Statistik, dan direset saat ganti profil.
- Cari: semua periode, profil aktif, hasil dikelompokkan per tanggal beserta total hasil.
- Bintang di form transaksi: pilih favorit untuk mengisi form; "Simpan sebagai favorit" di form edit.

## Review Focus
1. Filter tidak bocor antar profil dan total Statistik tetap sama dengan tab Transaksi saat filter aktif.
2. Pencarian dan favorit tidak menampilkan data profil lain.
3. Favorit dengan kategori/aset yang sudah dihapus tidak membuat form rusak.
