# CLAUDE.md

## Build, verifikasi UI & simulator

Setiap kali melakukan build, menjalankan app, verifikasi UI, tap/swipe/ketik,
screenshot, audit aksesibilitas, atau mengelola iOS Simulator (boot, erase,
permission, lokasi, push, appearance), WAJIB gunakan skill `ios-simulator-skill`
(`/ios-simulator-skill`) dan script-nya, bukan perintah `xcodebuild`/`simctl`
mentah atau menebak koordinat layar.

- Saat build dengan `build_and_test.py`, selalu pakai
  `--simulator "<nama>" --os <versi>` sesuai simulator yang sedang menyala
  (cek dengan `sim_list.py`). Jangan biarkan skill memilih sendiri, karena nama
  yang sama ada di beberapa versi iOS dan skill bisa menyalakan simulator kedua.
- Mulai dari `sim_health_check.sh` kalau ada tanda environment bermasalah.
- Cari elemen lewat label aksesibilitas (`screen_mapper.py`, `navigator.py`),
  bukan koordinat.
- Di laporan akhir, sebutkan skill/script yang dipakai dan hasil verifikasinya.
- Jika skill tidak tersedia di sesi (belum terdeteksi), hentikan dan beri tahu
  pengguna dulu, jangan diam-diam pakai cara lain.
