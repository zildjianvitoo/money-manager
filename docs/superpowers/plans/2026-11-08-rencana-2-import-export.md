# Rencana 2 — Import & Export

**Goal:** Memindahkan seluruh riwayat dari Money Manager ke aplikasi ini (F10) dan mengeluarkannya lagi (F11).

**Penyimpangan dari PRD (keputusan pemilik, 8 Nov 2026):** file asli pemilik ternyata **JSON backup** (`appName: "Money Manager"`, `version: 2.0`), bukan xlsx/csv. Maka:
- Import: **JSON backup** + **CSV**. xlsx ditunda.
- Export: **CSV** (UTF-8 BOM). Kolom: `Date, Account, Category, Subcategory, Note, Amount, Type, To Account, Fee, Description`.
- Pemetaan manual kategori/aset ditunda: item dicocokkan otomatis berdasarkan nama (tanpa beda huruf besar/kecil), yang tidak ketemu dibuat baru, dan pratinjau menampilkan daftarnya. Undo menghapus yang dibuat batch itu.
- File `.mmbak` (SQLite) tidak didukung.

**Format JSON backup:** `transactionType` 0 = pendapatan, 1 = pengeluaran (2 = transfer, belum pernah terlihat di data nyata, dilaporkan sebagai baris gagal). `category.parentCategoryId` ≠ null berarti subkategori. Tanggal tanpa zona waktu = waktu lokal. `wallets[].balance` = saldo sekarang, jadi saldo awal aset baru = saldo − selisih transaksi yang diimpor.

## Task
1. Model `ImportBatch` + masuk `MoneySchema`.
2. `ImportRow`, `FlexibleNumber`, `BackupJSONParser`, `CSVImportParser` (termasuk pasangan Transfer-Out/Transfer-In), `CSVExporter` — dites.
3. `ImportService`: pratinjau (jumlah, rentang, total per bulan, duplikat), commit satu kali simpan (rollback bila gagal), undo — dites.
4. UI: Lainnya → Import (pilih file, profil tujuan, pratinjau, hasil), Riwayat Import (undo), Export (share sheet).
5. Build, `swift test`, verifikasi simulator, laporan.

## Review Focus
1. Total pendapatan/pengeluaran per bulan setelah import sama dengan file sumber.
2. Import file yang sama dua kali tidak menambah transaksi.
3. Kegagalan di tengah tidak meninggalkan data setengah jadi.
4. Export → import ke profil kosong menghasilkan jumlah dan total per bulan yang sama.
