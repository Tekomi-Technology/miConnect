# Triển khai miConnect lên VPS (Cloudflare Proxy + port riêng)

```
Người dùng ──https──► miconnect.vn (Cloudflare, 443)
                         │  Origin Rule: port 5679
                         ▼
VPS :5679  (ufw: chỉ IP Cloudflare)  ──► Nginx (HTTPS, Origin Cert)
                                            │
                                            ▼
                               127.0.0.1:5680 ──► container rails:4000
```

- VPS không dùng 80/443. Port web: **5679**, chỉ dải IP Cloudflare vào được.
- SSH: port **24700**, chỉ qua VPN công ty.
- `rails` chỉ publish `127.0.0.1:5680`. Docker bỏ qua ufw, nên **không bao giờ** publish port không có `127.0.0.1:`.

## 1. Cloudflare (dashboard)

1. **DNS → Add record**: `A`, name `@`, content `<IP VPS>`, **Proxied (mây cam)**.
2. **Rules → Origin Rules → Create rule**: Hostname equals `miconnect.vn` → **Destination Port: Rewrite to `5679`**.
3. **SSL/TLS → Overview**: chế độ **Full (strict)**.
4. **SSL/TLS → Origin Server → Create Certificate** (RSA, hostname `miconnect.vn`, 15 năm).
   Giữ lại *Origin Certificate* và *Private Key*. Private key là bí mật: không commit, không gửi qua chat.

## 2. VPS (lần đầu)

```bash
# Nginx
apt install -y nginx
rm -f /etc/nginx/sites-enabled/default        # bỏ site mặc định nghe :80

# Origin Certificate
install -d -m 0700 /etc/ssl/cloudflare
nano /etc/ssl/cloudflare/miconnect.vn.pem      # dán Origin Certificate
nano /etc/ssl/cloudflare/miconnect.vn.key      # dán Private Key
chmod 600 /etc/ssl/cloudflare/miconnect.vn.*

# Site Nginx
cp ~/miConnect/deployment/vps/nginx/miconnect.conf /etc/nginx/sites-available/miconnect.conf
ln -sf /etc/nginx/sites-available/miconnect.conf /etc/nginx/sites-enabled/miconnect.conf

# Firewall chỉ cho Cloudflare + real IP cho Nginx (tự chạy nginx -t và reload)
~/miConnect/deployment/vps/cloudflare-firewall.sh 5679

# Cập nhật dải IP Cloudflare hằng tuần
( crontab -l 2>/dev/null; echo '0 4 * * 1 /root/miConnect/deployment/vps/cloudflare-firewall.sh 5679 >/var/log/cloudflare-firewall.log 2>&1' ) | crontab -
```

## 3. App

```bash
cd ~/miConnect
cp .env.example .env && chmod 600 .env   # điền DB, Redis, secret...
# FRONTEND_URL=https://miconnect.vn
# FORCE_SSL=true
docker compose -f docker-compose.production.yaml up -d --build
```

## 4. Kiểm tra

```bash
ufw status | grep 5679 | head -3                 # chỉ IP Cloudflare
ss -tulpn | grep -vE '127\.0\.0\.|\[::1\]'        # chỉ 24700, 5679 (+ 68/udp DHCP)
docker ps --format '{{.Names}}\t{{.Ports}}'       # không có 0.0.0.0:
curl -sI https://miconnect.vn | head -1           # HTTP/2 200 hoặc 302
```

Từ một máy ngoài (không qua Cloudflare), `https://<IP VPS>:5679` phải **timeout**.

## Deploy bản mới

```bash
cd ~/miConnect && git pull --ff-only
docker compose -f docker-compose.production.yaml up -d --build
```
Sửa cấu hình trong repo rồi commit/push, không sửa tay trên VPS.
