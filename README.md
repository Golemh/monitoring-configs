# monitoring-configs

Monitoring stack configuration — Prometheus, Grafana dashboards, and Docker Compose for the monitoring stack.

## Structure

```
monitoring-configs/
├── grafana/
│   ├── dashboards/
│   │   ├── kafka-overview.json
│   │   ├── kafka-broker-health.json
│   │   └── kafka-resource-utilization.json
│   └── provisioning/
│       ├── datasources/
│       │   └── prometheus.yml
│       └── dashboards/
│           └── dashboard.yml
│
├── prometheus/
│   ├── prometheus.yml               # Base config (self-monitoring only)
│   └── prometheus-azure-sd.yml      # Azure SD config (for Azure deployments)
│
└── docker-compose/
    └── monitoring-compose.yml
```

## Deployment

```bash
export MONITORING_USER_HOME="/home/kafkauser"
export GRAFANA_ADMIN_PASSWORD="your-password"

# For Azure deployments, use the Azure SD prometheus config:
cp prometheus/prometheus-azure-sd.yml prometheus/prometheus.yml

cd docker-compose
docker compose -f monitoring-compose.yml up -d
```

## Required Environment Variables

| Variable | Default | Description |
|---|---|---|
| `MONITORING_USER_HOME` | — | Home directory of the deploy user |
| `GRAFANA_ADMIN_PASSWORD` | — | Grafana admin UI password |
| `PROMETHEUS_RETENTION` | `15d` | Prometheus data retention period |

### Azure SD Config
| Variable | Description |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID for service discovery |
| `AZURE_SD_CLIENT_ID` | Managed identity client ID for Azure SD auth |

## Docker Image Versions

| Image | Version | Previous |
|---|---|---|
| `prom/prometheus` | `v3.2.1` | `:latest` |
| `grafana/grafana` | `11.5.2` | `:latest` |
