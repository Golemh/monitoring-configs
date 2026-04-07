#!/bin/bash
# bootstrap.sh — Monitoring stack setup (Prometheus + Grafana + Loki)
# Called by cloud-init after packages, Docker, and disk mount are ready.
# Reads configuration from /opt/bootstrap-config.json.

set -euo pipefail

CONFIG_FILE="/opt/bootstrap-config.json"
USERNAME=$(jq -r '.username' "$CONFIG_FILE")
AWS_REGION=$(jq -r '.aws_region' "$CONFIG_FILE")
GRAFANA_PASSWORD=$(jq -r '.grafana_password' "$CONFIG_FILE")
PROMETHEUS_RETENTION=$(jq -r '.prometheus_retention' "$CONFIG_FILE")
HOME_DIR="/home/${USERNAME}"

echo "=== Monitoring bootstrap ==="

# --- Data directories (Prometheus=65534, Loki=10001, Grafana=472) ---
mkdir -p /data/prometheus /data/grafana /data/loki
chown -R 65534:65534 /data/prometheus
chown -R 10001:10001 /data/loki
chown -R 472:472 /data/grafana

# --- Prometheus config (AWS EC2 service discovery) ---
cp "${HOME_DIR}/monitoring-configs/prometheus/prometheus-aws-sd.yml" \
   "${HOME_DIR}/monitoring-configs/prometheus/prometheus.yml"
sed -i "s|\${AWS_REGION}|${AWS_REGION}|g" \
   "${HOME_DIR}/monitoring-configs/prometheus/prometheus.yml"

# --- Docker Compose setup ---
cp "${HOME_DIR}/monitoring-configs/docker-compose/monitoring-compose.yml" \
   "${HOME_DIR}/docker-compose.yml"

# --- Write .env ---
cat > "${HOME_DIR}/.env" <<ENVEOF
MONITORING_USER_HOME=${HOME_DIR}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
PROMETHEUS_RETENTION=${PROMETHEUS_RETENTION}
ENVEOF

# --- Dashboards directory for Grafana provisioning ---
mkdir -p "${HOME_DIR}/monitoring-configs/grafana/dashboards"

# --- Fix ownership ---
chown -R "${USERNAME}:${USERNAME}" "${HOME_DIR}"

# --- Start monitoring stack ---
echo "  Starting Prometheus, Grafana, Loki..."
cd "${HOME_DIR}" && docker compose up -d

# --- Node exporter ---
install_node_exporter() {
  local version="1.10.2"
  echo "  Installing node_exporter v${version}..."
  curl -sL "https://github.com/prometheus/node_exporter/releases/download/v${version}/node_exporter-${version}.linux-amd64.tar.gz" \
    -o /tmp/node_exporter.tar.gz
  tar xzf /tmp/node_exporter.tar.gz -C /tmp
  mv "/tmp/node_exporter-${version}.linux-amd64/node_exporter" /usr/local/bin/
  rm -rf /tmp/node_exporter*

  cat > /etc/systemd/system/node-exporter.service <<'SVCEOF'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/node_exporter
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl enable --now node-exporter.service
}

# --- Spot watcher ---
install_spot_watcher() {
  echo "  Installing spot-watcher daemon..."
  cat > /opt/spot-watcher.sh <<WATCHEREOF
#!/bin/bash
TOKEN=\$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \\
  -H "X-aws-ec2-metadata-token-ttl-seconds: 30")
ACTION=\$(curl -sf -H "X-aws-ec2-metadata-token: \$TOKEN" \\
  "http://169.254.169.254/latest/meta-data/spot/instance-action" 2>/dev/null)
if [ \$? -eq 0 ] && [ -n "\$ACTION" ]; then
  logger -t spot-watcher "Interruption warning received: \$ACTION"
  cd /home/${USERNAME} && docker compose stop
  sync
  logger -t spot-watcher "Graceful shutdown complete"
fi
WATCHEREOF
  chmod +x /opt/spot-watcher.sh

  cat > /etc/systemd/system/spot-watcher.service <<'SVCEOF'
[Unit]
Description=EC2 Spot Interruption Watcher
After=network-online.target
[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /opt/spot-watcher.sh; sleep 5; done'
Restart=always
[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl enable --now spot-watcher.service
}

install_node_exporter
install_spot_watcher

echo "=== Monitoring bootstrap complete ==="
