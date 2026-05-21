# Commands and Configuration Reference

This file contains all shell commands, systemd unit files, and configuration file contents referenced in `README.md`.

---

## Prometheus and Grafana Installation

Run the following on the **Central-Monitor** node.

```bash
# Connect to the monitoring node
ssh -i your-key.pem ubuntu@<monitor-node-ip>

# Refresh package lists and install wget
sudo apt-get update -y
sudo apt-get install -y wget

# Download and install Prometheus
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz
tar xvfz prometheus-2.48.0.linux-amd64.tar.gz
sudo mv prometheus-2.48.0.linux-amd64 /opt/prometheus

# Register Prometheus as a systemd service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Metrics Server
After=network.target

[Service]
User=root
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/opt/prometheus/data
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Prometheus
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# Add Grafana APT repository and install
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update -y
sudo apt-get install -y grafana

# Enable and start Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

---

## Node Exporter Installation

Run the following on **each application node** (Node-1 and Node-2).

```bash
# Connect to the application node
ssh -i your-key.pem ubuntu@<app-node-ip>

# Download and install Node Exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz
sudo mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Register Node Exporter as a systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter - System Metrics Agent
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Node Exporter
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
```

---

## Prometheus Configuration

File path: `/opt/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - "alerting_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets:
        - '<app-node-1-ip>:9100'
        - '<app-node-2-ip>:9100'
```

After editing, restart Prometheus to apply changes:

```bash
sudo systemctl restart prometheus
```

---

## Alerting Rules

File path: `/opt/prometheus/alerting_rules.yml`

```yaml
groups:
  - name: infrastructure_alerts
    interval: 30s
    rules:
      - alert: CPUUsageHigh
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 70
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "CPU usage has exceeded the 70% threshold"

      - alert: MemoryUsageHigh
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
        for: 2m
        labels:
          severity: warning

      - alert: DiskUsageHigh
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 80
        for: 2m
        labels:
          severity: warning
```

---

## Alert Testing

Run the following on a target application node to simulate high CPU load.

```bash
# Connect to the target node
ssh -i your-key.pem ubuntu@<app-node-ip>

# Install the stress utility
sudo apt-get update
sudo apt-get install -y stress

# Simulate 70%+ CPU load for 5 minutes
stress --cpu 4 --timeout 300s
```

---

## Troubleshooting

### Prometheus Not Collecting Metrics

```bash
# Tail Prometheus logs
sudo journalctl -u prometheus -f

# Validate configuration file
sudo nano /opt/prometheus/prometheus.yml

# Restart the service
sudo systemctl restart prometheus
```

### Node Exporter Offline

```bash
# Check service health
sudo systemctl status node_exporter

# Review recent logs
sudo journalctl -u node_exporter -n 50

# Force restart
sudo systemctl restart node_exporter
```

### Grafana Not Rendering Dashboards

```bash
# Verify Grafana is running
sudo systemctl status grafana-server

# Follow live logs
sudo journalctl -u grafana-server -f

# Restart the server
sudo systemctl restart grafana-server
```
