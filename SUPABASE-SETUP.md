# Panduan Supabase — Pemuda Channel (Android)

## A. Ambil kredensial publik
1. Buka https://supabase.com/dashboard dan pilih project.
2. Buka Project Settings → API Keys (pada tampilan lama: Settings → API).
3. Salin Project URL dan Publishable key. Untuk project lama, gunakan `anon` public key.
4. Jangan salin `service_role` atau secret key ke website.

## B. Sambungkan website
1. Deploy website ke Vercel atau buka melalui web server lokal (jangan mengandalkan `file://` untuk semua fungsi browser).
2. Tekan tombol **Supabase** pada header.
3. Tempel Project URL dan Publishable/anon key, tekan **Simpan konfigurasi**.
4. Tekan **Uji koneksi database**. Jika gagal, jalankan SQL pada bagian C lalu uji lagi.
5. Konfigurasi melalui UI disimpan di localStorage browser yang digunakan; jika membuka website dari browser/perangkat lain, masukkan lagi URL/key. Key publik bukan password rahasia, tetapi RLS wajib benar.

## C. Buat tabel dan aturan akses
1. Buka Supabase → SQL Editor → New query.
2. Buka `supabase/schema.sql` dari ZIP dan salin seluruh isinya.
3. Tempel ke SQL Editor dan tekan Run.
4. Jika ada error SQL, berhenti dan perbaiki error itu sebelum membuka website untuk publik. Jangan menganggap database siap hanya karena sebagian query berhasil.

## D. Aktifkan autentikasi
1. Buka Authentication → URL Configuration.
2. Atur Site URL ke domain website Vercel.
3. Tambahkan URL preview/deployment ke Redirect URLs bila digunakan.
4. Daftar lewat tombol Gabung. Jika konfirmasi email aktif, buka email konfirmasi dahulu.

## E. Jadikan akun pertama Owner
1. Buka Authentication → Users dan salin UUID akun yang Anda percaya.
2. Di SQL Editor jalankan, ganti placeholder dengan UUID yang benar:

```sql
update public.profiles
set role = 'owner'
where id = 'UUID_PENGGUNA';
```

Jangan pernah menyediakan pengaturan role Owner/Admin untuk pengguna umum. Jalankan perubahan role hanya dari SQL Editor tepercaya.

## F. Tes wajib sebelum produksi
- Akun A dapat mendaftar, masuk, membuat channel, membuat postingan, mengikuti channel, memberi reaksi, dan mengomentari postingan.
- Akun B melihat data publik yang sama tetapi tidak dapat mengubah data milik akun A.
- Channel privat tidak terlihat/terbaca akun yang tidak memiliki akses.
- Pengguna biasa tidak dapat mengubah role menjadi admin/owner.
- Uji upload media dan notifikasi setelah integrasi fitur tersebut selesai.

## Troubleshooting
- **SDK tidak termuat:** pastikan internet aktif dan CDN `cdn.jsdelivr.net` tidak diblokir.
- **Invalid API key:** pastikan memakai Publishable key atau `anon` public key, bukan secret/service_role.
- **relation/table not found:** jalankan `supabase/schema.sql`.
- **permission denied / RLS error:** periksa policy tabel dan pastikan login; jangan mematikan RLS sebagai jalan pintas.
- **Sign-up berhasil tetapi belum login:** periksa email confirmation pada Supabase Auth.
