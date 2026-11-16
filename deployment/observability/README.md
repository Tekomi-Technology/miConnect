# Observability cho Chatwoot

Stack gọn chạy trên chính VPS: Grafana, Loki (log, giữ 5 ngày), Prometheus (metrics, giữ 10 ngày / tối đa 1GB), Grafana Alloy (thu log docker), node_exporter, cAdvisor, redis_exporter. Mỗi container có `mem_limit` và `cpus`. Alert dùng Grafana Alerting (không Alertmanager).

## Triển khai
```bash
cd /home/its/observability          # copy thư mục này lên VPS
cp .env.example .env && chmod 600 .env   # đặt GRAFANA_ADMIN_PASSWORD, REDIS_PASSWORD (lấy từ .env của chatwoot)
docker compose -f docker-compose.observability.yml --env-file .env up -d
```
Compose dùng network external `chatwoot_default` (chỉ redis-exporter tham gia, để đọc Redis).

## Truy cập Grafana (qua VPN WireGuard)
Grafana chỉ nghe ở IP VPN của VPS: `GRAFANA_BIND_ADDR=10.78.0.1` (không nghe IP public/0.0.0.0). Truy cập: bật tunnel WireGuard trên laptop rồi mở `http://10.78.0.1:3300`.

VPN (khác mạng PBX 10.77.0.0/24, cùng cách làm như `pbx-freeswitch-pool/deployment/wireguard`):

| Mục | Giá trị |
| --- | --- |
| Server | `wg0` = `10.78.0.1/24`, UDP `51821`, `wg-quick@wg0` (systemd, enable) |
| Peer laptop | `10.78.0.2/32`, split tunnel: `AllowedIPs = 10.78.0.0/24`, keepalive 25 |
| File khoá server | `/etc/wireguard/{server.key,server.pub,wg0.conf}` (root, 0600); không commit |
| Firewall host | ufw inactive, iptables INPUT ACCEPT: không cần mở thêm. Nếu có firewall của nhà cung cấp VPS thì mở UDP 51821 |

Thứ tự khởi động: Docker publish cổng vào `10.78.0.1` nên cần `wg0` lên trước. Đã thêm drop-in `/etc/systemd/system/docker.service.d/wg0.conf` (`After=` và `Wants=wg-quick@wg0.service`).

Thêm thiết bị: trên VPS (root), sinh keypair, thêm khối `[Peer]` (`PublicKey`, `AllowedIPs = 10.78.0.N/32`) vào `/etc/wireguard/wg0.conf` và `wg set wg0 peer <pub> allowed-ips 10.78.0.N/32` (không cần restart). Client config: `Address = 10.78.0.N/32`, `Endpoint = 210.211.97.224:51821`, `AllowedIPs = 10.78.0.0/24`, `PersistentKeepalive = 25`. Xoá peer: bỏ khối `[Peer]` và `wg set wg0 peer <pub> remove`. Không để private key client trên VPS.

Đổi bind: sửa `.env` rồi `docker compose -f docker-compose.observability.yml up -d --no-deps grafana`. Khẩn cấp khi VPN lỗi: tạm đặt `GRAFANA_BIND_ADDR=127.0.0.1` và dùng `ssh -p 2202 -N -L 3300:127.0.0.1:3300 its@210.211.97.224`. Loki/Prometheus/Alloy chỉ nằm trong docker network, không publish cổng.

## Dashboards (thư mục Observability)
- Tổng quan hạ tầng: host, container (CPU/RAM/mạng/restart), đĩa.
- Log explorer: lọc theo service, tìm kiếm, dòng lỗi, HTTP status/5xx của rails.
- Redis và Sidekiq: độ dài các queue, retry/dead/scheduled, hiệu năng Redis.

## Alert rules (provisioned)
Container down/restart, target giám sát down, đĩa > 85%, RAM available < 10%, 5xx rails, Redis down, Sidekiq tồn đọng > 1000 job. Contact point `telegram` đọc `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` từ `.env`; để trống thì alert vẫn đánh giá nhưng gửi thông báo sẽ lỗi (chỉ ghi log) cho đến khi điền.

## Bật log JSON và request_id của Chatwoot
Rule 5xx và panel HTTP status cần lograge: đặt `LOGRAGE_ENABLED=true` trong `.env` của chatwoot rồi recreate `rails` (đã bật trên VPS dev; sidekiq không có log HTTP nên không cần). Dòng log của Rails có tiền tố logger (`I, [ts #1] INFO -- : [uuid] {json}`); Alloy trích phần JSON để gắn label `status` và lưu dòng JSON thuần. `request_id` trong log cần build lại image có thay đổi `config/initializers/lograge.rb`.

## Ghi chú
- Chatwoot/Sidekiq không có endpoint `/metrics`; số liệu Sidekiq lấy qua độ dài key Redis (`queue:*`, `retry`, `dead`, `schedule`).
- cAdvisor cần bản >= v0.55 để nhận container khi Docker dùng containerd snapshotter.
- Alloy mount `docker.sock` (read-only) để discovery và đọc log container.
