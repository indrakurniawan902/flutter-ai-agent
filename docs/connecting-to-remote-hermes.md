# Connecting Flames to Any Remote Hermes Agent

Panduan lengkap menghubungkan aplikasi **Flames** di smartphone ke instance **Hermes Agent** milik orang lain (misal: teman kantor, server kantor, atau laptop kedua).

---

## 1. Pertanyaan Kunci: Apakah Harus di 1 Network (WiFi yang Sama)?

**Jawabannya: TIDAK HARUS.**

Ada 2 skenario konektivitas:

### Skenario A: Di 1 Jaringan WiFi yang Sama (LAN Lokal)
- **Kondisi**: HP kamu dan laptop teman terhubung ke WiFi kantor yang sama.
- **Kelebihan**: Gak butuh kuota internet, latency sangat cepat, gak butuh domain publik.
- **URL yang dipakai**: IP lokal laptop teman, contoh: `http://192.168.1.45:8642/v1`.

### Skenario B: Beda Jaringan (Remote / WFH / Pakai Data Seluler)
- **Kondisi**: HP kamu pakai paket data 4G/5G, teman ada di rumah atau beda WiFi.
- **Kebutuhan**: Laptop teman harus punya pintu masuk publik. Paling mudah & gratis:
  1. **Cloudflare Tunnel (Paling Recommended)**: `cloudflared tunnel --url http://localhost:8642` → dapet URL HTTPS aman (contoh: `https://hermes-teman.trycloudflare.com/v1`).
  2. **Tailscale VPN**: HP dan laptop teman gabung ke jaringan Tailscale yang sama → pakai IP Tailscale `http://100.x.y.z:8642/v1`.
  3. **VPS / Public Domain**: Seperti yang kita pakai di `https://indra-9router.my.id/v1`.

---

## 2. Langkah di Laptop Teman (Host Hermes)

Minta teman kantormu melakukan 3 langkah ini di laptopnya:

### Langkah 2.1: Aktifkan API Server Hermes
Buka file konfigurasi Hermes teman: `~/.hermes/config.yaml`
Pastikan konfigurasi `api_server` aktif dan listen ke `0.0.0.0`:

```yaml
platforms:
  api_server:
    enabled: true
    host: 0.0.0.0    # Wajib 0.0.0.0 agar bisa diakses device luar di jaringan yang sama
    port: 8642
```

### Langkah 2.2: Buat Token / Password Akses
Buka file `~/.hermes/.env` di laptop teman, tentukan API key:
```bash
API_SERVER_KEY=teman-secret-key-123
```

Lalu restart gateway Hermes di laptopnya:
```bash
hermes gateway restart
```

### Langkah 2.3: Berikan Info URL & Token ke Kamu
Minta teman cek IP lokalnya:
- **Mac**: `ipconfig getifaddr en0` (misal: `192.168.1.45`)
- **Linux**: `hostname -I | awk '{print $1}'`
- **Windows**: `ipconfig`

Format koneksinya:
- **Base URL**: `http://192.168.1.45:8642/v1`
- **Token**: `teman-secret-key-123`

*(Opsional)* Temanmu bisa langsung generate QR code pairing di terminalnya:
```bash
qrencode -t ansiutf8 '{"gatewayUrl":"http://192.168.1.45:8642/v1","token":"teman-secret-key-123","profileName":"Hermes Andi"}'
```

---

## 3. Langkah di HP Kamu (App Flames)

### Cara 1: Scan QR Code (Instan)
1. Buka app **Flames** di HP.
2. Masuk ke tab **Settings** (icon gerigi).
3. Tap tombol **Scan QR Code**.
4. Arahkan kamera HP ke QR Code di layar laptop temanmu.
5. Profil temanmu otomatis tersimpan dan aktif!

### Cara 2: Input Manual (+ Add Profile)
1. Buka app **Flames** → masuk ke tab **Settings**.
2. Di bagian **Server Profiles**, tap **+ Add Profile**.
3. Masukkan data:
   - **Profile Name**: `Hermes Andi (Kantor)`
   - **Gateway / Base URL**: `http://192.168.1.45:8642/v1`
   - **Token**: `teman-secret-key-123`
4. Tap **Save Profile**.

---

## 4. Cara Konek ke Profile Khusus Teman (Multiplex Profiles)

Kalau teman kantor punya beberapa profile di Hermes-nya (misal punya profile `@dev`, `@ops`, atau profil custom):

Hermes mendukung URL prefix otomatis:
- **Default / Generalist Profile**: `http://192.168.1.45:8642/v1`
- **Profile Dev Teman**: `http://192.168.1.45:8642/p/dev/v1`
- **Profile Ops Teman**: `http://192.168.1.45:8642/p/ops/v1`

Tinggal masukkan URL di atas saat membuat profile baru di Flames.

---

## 5. Switch Profil Bebas Kapan Saja
Di tab **Settings** app Flames, ada dropdown **Server Profiles**:
- Tap dropdown, kamu bisa bebas pindah antara:
  - `VPS Oracle` (Hermes kamu di cloud)
  - `Hermes Mac` (Laptop pribadimu)
  - `Hermes Andi` (Laptop teman kantormu)
- Setiap kali profil di-switch, chat berikutnya akan langsung mengarah ke server yang dipilih!
