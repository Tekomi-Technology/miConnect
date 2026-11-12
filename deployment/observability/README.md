# Observability cho Chatwoot

Stack gọn chạy trên chính VPS: Grafana, Loki (log, giữ 5 ngày), Prometheus (metrics, giữ 10 ngày / tối đa 1GB), Grafana Alloy (thu log docker), node_exporter, cAdvisor, redis_exporter. Mỗi container có `mem_limit` và `cpus`. Alert dùng Grafana Alerting (không Alertmanager).

## Triển khai
```bash
cd /home/its/observability          # copy thư mục này lên VPS
cp .env.example .env && chmod 600 .env   # đặt GRAFANA_ADMIN_PASSWORD, REDIS_PASSWORD (lấy từ .env của chatwoot)
docker compose -f docker-compose.observability.yml --env-file .env up -d
```
Compose dùng network external `chatwoot_default` (chỉ redis-exporter tham gia, để đọc Redis).

## Truy cập Grafana
Grafana bind vào `GRAFANA_BIND_ADDR` (mặc định `127.0.0.1:3300`). Khi chưa có VPN dùng SSH tunnel:
```bash
ssh -p 2202 -N -L 3300:127.0.0.1:3300 its@210.211.97.224   # rồi mở http://localhost:3300
```
Khi có WireGuard: đổi `GRAFANA_BIND_ADDR` thành IP VPN của VPS trong `.env` và `docker compose ... up -d grafana`. Loki/Prometheus/Alloy chỉ nằm trong docker network, không publish cổng.

## Dashboards (thư mục Observability)
- Tổng quan hạ tầng: host, container (CPU/RAM/mạng/restart), đĩa.
- Log explorer: lọc theo service, tìm kiếm, dòng lỗi, HTTP status/5xx của rails.
- Redis và Sidekiq: độ dài các queue, retry/dead/scheduled, hiệu năng Redis.

## Alert rules (provisioned)
Container down/restart, target giám sát down, đĩa > 85%, RAM available < 10%, 5xx rails, Redis down, Sidekiq tồn đọng > 1000 job. Contact point `telegram` đọc `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` từ `.env`; để trống thì alert vẫn đánh giá nhưng gửi thông báo sẽ lỗi (chỉ ghi log) cho đến khi điền.

## Bật log JSON và request_id của Chatwoot
Rule 5xx và panel HTTP status cần lograge: đặt `LOGRAGE_ENABLED=true` trong `.env` của chatwoot rồi recreate `rails` (và `sidekiq` nếu muốn). `request_id` trong log cần build lại image có thay đổi `config/initializers/lograge.rb`.

## Ghi chú
- Chatwoot/Sidekiq không có endpoint `/metrics`; số liệu Sidekiq lấy qua độ dài key Redis (`queue:*`, `retry`, `dead`, `schedule`).
- cAdvisor cần bản >= v0.55 để nhận container khi Docker dùng containerd snapshotter.
- Alloy mount `docker.sock` (read-only) để discovery và đọc log container.
