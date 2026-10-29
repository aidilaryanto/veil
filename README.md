# PilihLayar v2

Aplikasi macOS gratis untuk berbagi layar presentasi: pilih jendela atau
aplikasi yang ingin ditampilkan, atur kanvas dan kamera, lalu bagikan
jendela Output di Zoom, Google Meet, atau Microsoft Teams. PilihLayar
ditulis dari nol dengan SwiftUI dan ScreenCaptureKit, dengan kode asli.

## Fitur

- **Sources**: daftar jendela yang dikelompokkan per aplikasi, dengan
  pencarian, mode Allow List dan Block List, serta tombol Clear dan Refresh.
- **Display**: pilih layar yang ditangkap, dengan penjelasan Full Display
  dan Isolated di dalam popup.
- **Framing & Canvas**: framing Full (seluruh layar) atau Dynamic
  (area tangkapan mengikuti gabungan bingkai jendela yang dipilih);
  kanvas Full Display atau Isolated, dengan latar abu-abu, putih, hitam,
  atau gambar custom.
- **Presets**: tiga preset bawaan (Presentasi, Demo Aplikasi, Layar Penuh),
  plus preset custom yang bisa disimpan, diterapkan, dan dihapus.
  Preset tersimpan di UserDefaults dengan key `PilihLayar.v2.presets`.
- **Camera**: overlay kamera dengan 9 posisi, 3 bentuk (lingkaran, kotak,
  membulat), ukuran 100–320, dan opsi mirror.
- **Files**: sumber file PDF (navigasi halaman penuh lewat PDFKit) dan
  PPT/PPTX (pratinjau slide pertama lewat QuickLook).
- **Panic**: tombol Panik dan pintasan `Cmd+Shift+P` langsung menghitamkan
  output dan menghentikan capture.
- **Always on Top**: jendela kontrol dibuat floating secara default,
  sedangkan jendela Output dibiarkan normal supaya tidak menutupi
  pekerjaan lain.
- **Pintasan**: `Cmd+Shift+P` untuk Panik, `Cmd+Shift+S` untuk
  Mulai/Berhenti Stream.

## Cara build via Xcode

1. Buka folder proyek ini di Xcode, atau jalankan dari Terminal:
   `swift build -c release`
2. Izinkan Screen Recording dan Camera saat aplikasi pertama kali
   memintanya (System Settings > Privacy & Security).
3. Tekan Refresh, pilih jendela, tekan Mulai Stream, lalu buka Preview.

## Cara build via GitHub Actions

Setiap push ke branch `main` (atau pemicu manual) menjalankan workflow
`.github/workflows/build-macos.yml`: build release, membungkus biner
menjadi `PilihLayar.app`, menandatangani secara ad-hoc, lalu mengunggah
artefak bernama `PilihLayar-macOS`. Unduh artefak itu dari tab Actions
di repositori, ekstrak, lalu buka dengan klik kanan > Open pada
peluncuran pertama (tanda tangan ad-hoc bukan Developer ID).

## Cara pakai

1. Tekan Refresh dan pilih jendela di popup Sources.
2. Atur Display, Framing, Canvas, dan Camera bila perlu, atau terapkan
   sebuah preset.
3. Tekan Mulai Stream, lalu tekan Preview untuk membuka jendela
   "PilihLayar Output — bagikan jendela ini".
4. Di Zoom/Meet/Teams, pilih Share Screen > Window > jendela Output
   tersebut, bukan seluruh layar.
5. Untuk menyembunyikan output seketika, tekan Panik
   (`Cmd+Shift+P`). Tekan Mulai Stream lagi untuk melanjutkan.

## Yang sengaja tidak ada

- **Tanpa sistem lisensi**: aplikasi ini gratis dan tidak punya validasi
  lisensi, kunci, aktivasi, atau pembatasan preset berbayar.
- **Tanpa kamera virtual / DriverKit**: tidak ada kamera virtual.
  Yang dibagikan adalah jendela Output biasa.
- **Tanpa menyalin aset/branding aplikasi referensi**: nama, ikon,
  aset, dan kalimat dari aplikasi lain tidak dipakai di sini.
  Yang ditiru hanyalah gagasan fungsinya, diimplementasikan ulang
  dengan kode asli.
- **PPT hanya pratinjau slide pertama**: macOS tidak punya renderer
  slide-per-slide bawaan untuk PPT/PPTX, jadi yang ditampilkan adalah
  thumbnail QuickLook. Untuk navigasi slide penuh, konversi PPT ke PDF
  dulu, lalu tambahkan PDF-nya sebagai sumber file.
