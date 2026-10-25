# Pemuda Channel — frontend + Supabase foundation

Website statis responsif (HTML/CSS/JavaScript) untuk Pemuda Channel. Project URL dan public key dapat dimasukkan dari tombol **Supabase** pada header atau melalui `supabase-config.js`.

## File penting
- `index.html`, `styles.css`, `app.js` — antarmuka.
- `supabase-config.js` — konfigurasi publik opsional.
- `supabase-bridge.js` — Supabase JS v2, autentikasi dan helper database.
- `supabase/schema.sql` — tabel, indeks, trigger, RLS policies dan bucket Storage.
- `SUPABASE-SETUP.md` — panduan konfigurasi dari Android.
- `vercel.json` — konfigurasi deploy statis.

## Setup Supabase
1. Buat/pilih project di https://supabase.com/dashboard.
2. Ambil Project URL dan **Publishable key** (atau `anon` public key project lama) dari Project Settings → API Keys.
3. Deploy website, tekan **Supabase** di header, masukkan URL/key, lalu simpan.
4. Di Supabase SQL Editor jalankan seluruh isi `supabase/schema.sql`.
5. Di Authentication → URL Configuration, atur Site URL ke domain Vercel dan tambahkan domain deployment ke Redirect URLs.
6. Uji koneksi lewat tombol Supabase di website.
7. Buat akun melalui form Masuk/Gabung. Jika email confirmation aktif, konfirmasi email dahulu.
8. Untuk mengangkat akun pertama menjadi Owner, ambil UUID akun di Authentication → Users lalu jalankan dari SQL Editor: `update public.profiles set role='owner' where id='UUID_PENGGUNA';`.

## Status implementasi (penting)
- Supabase config UI dan uji akses tabel `channels`: tersedia.
- Supabase Auth sign-up/sign-in/sign-out: terhubung saat konfigurasi valid.
- Membaca channel/postingan dari Supabase: tersedia pada pemuatan awal setelah koneksi terkonfigurasi.
- Membuat channel, membuat postingan, mengikuti/berhenti mengikuti channel, reaksi suka, komentar: helper/aksi Supabase sudah disambungkan; harus diuji terhadap project dan policy milik Anda.
- Video, upload media, notifikasi otomatis/realtime, halaman manajemen Owner/Admin lengkap, dan seluruh tampilan statistik: belum terintegrasi penuh ke database. Kartu video dan sebagian demo lokal tetap contoh frontend.
- Fitur privat dibatasi oleh RLS untuk query database, tetapi harus diuji dengan akun pemilik, anggota, dan akun lain sebelum dipakai untuk data rahasia. Jangan menganggap aman sebelum pengujian.

## Keamanan
- Hanya gunakan Publishable key / `anon` public key di browser.
- Jangan pernah memasukkan `service_role` key atau secret key ke file frontend, repository, atau Vercel client-side environment.
- RLS bukan pengganti pengujian. Jalankan SQL dan uji hak akses dengan lebih dari satu akun.
- Bucket `pc-media` privat; bucket avatar publik. UI upload media belum selesai disambungkan.
- File ini tidak bisa langsung terkoneksi ke project Supabase milik Anda sampai URL/key dimasukkan dan SQL dijalankan.

## Deploy Vercel
Upload isi ZIP ke repository GitHub (pastikan `index.html` berada di root), lalu import repository itu di Vercel. Tidak perlu build command untuk versi HTML statis ini.
