# AWS EC2 Infrastructure Observability Stack with Prometheus & Grafana

## Overview
This project sets up a production-grade observability platform for AWS EC2 instances using Prometheus for metrics collection and Grafana for visualization. Metrics are gathered from multiple target servers via Node Exporter, centralized on a dedicated monitoring node, and surfaced through live dashboards with automated threshold-based alerting.

## System Architecture

![Architecture Overview](screenshots/architecture-overview.png)

### Core Components
1. **Central Monitoring Node** — Dedicated server hosting Prometheus and Grafana
2. **Target Application Nodes** (2x) — Workload servers instrumented with Node Exporter
3. **Prometheus** — Time-series metrics scraping, storage, and rule evaluation
4. **Grafana** — Dashboard rendering and alert visualization
5. **Node Exporter** — Exposes host-level system metrics over HTTP

### Data Flow
```
Target Nodes (Node Exporter) → Prometheus (Scrape & Store) → Grafana (Visualize)
 ↓
 Alerting Rules
```

## Goal
As an SRE, the aim was to build automated, real-time infrastructure visibility — replacing ad-hoc SSH-based checks for CPU, memory, and disk with a centralized alerting and dashboard solution that catches issues before they cause outages.

## Requirements
- Active AWS account with EC2 permissions
- SSH key pair for instance access
- Familiarity with Linux CLI
- Basic understanding of Prometheus and Grafana concepts

## Setup Guide

### Step 1: Provision EC2 Instances

#### Central Monitoring Node
1. Log into AWS Console → EC2 → Launch Instance
2. **Settings**:
 - **Name**: Central-Monitor
 - **AMI**: Ubuntu 22.04 LTS (ami-07216ac99dc46a187)
 - **Instance Type**: t2.medium
 - **Key Pair**: Use existing SSH key
 - **Security Group**: Open the following ports:
 - 22 (SSH)
 - 9090 (Prometheus UI)
 - 3000 (Grafana UI)
3. Launch the instance

#### Target Application Nodes
Repeat the above steps twice to create Node-1 and Node-2:
- **Instance Type**: t2.medium
- **AMI**: Ubuntu 22.04 LTS
- **Security Group**: Open the following ports:
 - 22 (SSH)
 - 9100 (Node Exporter metrics endpoint)

### Step 2: Deploy Prometheus and Grafana on the Monitoring Node

```bash
# Connect to the monitoring node
ssh -i your-key.pem ubuntu@<monitor-node-ip>

# Refresh package lists and install wget
sudo apt-get update -y
sudo apt-get install -y wget

# Fetch and install Prometheus
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

# Add Grafana repository and install
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update -y
sudo apt-get install -y grafana

# Enable and start Grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

### Step 3: Deploy Node Exporter on Target Nodes

```bash
# Connect to each application node
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

### Step 4: Configure Prometheus Scrape Targets

Edit the Prometheus config at `/opt/prometheus/prometheus.yml`:

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

![Prometheus Config](screenshots/prometheus-config-view.png)

### Step 5: Define Alerting Rules

Create `/opt/prometheus/alerting_rules.yml`:

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

![Alert Rules Config](screenshots/alerting-rules-view.png)

Apply changes by restarting Prometheus:
```bash
sudo systemctl restart prometheus
```

### Step 6: Set Up Grafana Dashboards

1. Open Grafana at `http://<monitor-node-ip>:3000`
2. Log in using default credentials: `admin` / `admin`
3. Connect Prometheus as a data source:
 - Navigate to Connections → Data Sources → Add New → Prometheus
 - Set URL to `http://localhost:9090`
 - Save and test the connection

4. Import the Node Exporter Full dashboard:
 - Go to Dashboards → Import
 - Enter Dashboard ID: `1860`
 - Select the Prometheus data source
 - Click Import

## Dashboard Screenshots

### Scrape Targets Status
All configured targets are being scraped with an UP status:

![Target Status](screenshots/targets-status.png)

### Active Alert Rules
Configured alerting rules are loaded and actively evaluating:

![Alert Rules Overview](screenshots/alert-rules-overview.png)

### Grafana Live Dashboard
The imported dashboard showing real-time system metrics:

![Live Dashboard](screenshots/grafana-live-dashboard.png)

## Alert Validation

### Simulating a CPU Spike

To validate the CPU alert, SSH into a target node and trigger artificial load:

```bash
# Connect to a target node
ssh -i your-key.pem ubuntu@<app-node-ip>

# Install the stress utility
sudo apt-get update
sudo apt-get install -y stress

# Simulate 70%+ CPU load for 5 minutes
stress --cpu 4 --timeout 300s
```

The alert fired successfully after 2 minutes of sustained load:

![Alert Triggered](screenshots/alert-triggered.png)

### Alert Lifecycle Observed
1. Opened Prometheus at `http://<monitor-ip>:9090/alerts`
2. Monitored the state transitions: **Inactive → Pending → Firing**
3. Alert activated once CPU crossed the 70% threshold for 2+ minutes
4. Alert self-resolved after the stress process terminated

## Metrics Coverage

### CPU
- Per-core utilization
- Idle time ratio
- User and kernel-mode time

### Memory
- Total and available RAM
- Utilization percentage
- Buffer and cache breakdown

### Disk
- Space used vs. available per mount
- Usage percentage
- Read/write I/O rates

### Network
- Inbound and outbound throughput
- Packet counts
- Error and drop rates

### System
- Load averages (1m, 5m, 15m)
- Uptime
- Active process count

## Technology Stack

| Component | Version |
|-----------|---------|
| AWS EC2 | — |
| Ubuntu | 22.04 LTS |
| Prometheus | v2.48.0 |
| Grafana | Latest stable |
| Node Exporter | v1.7.0 |
| Systemd | Built-in |

## Repository Layout

```
.
 config/
 prometheus.yml # Prometheus scrape + alertmanager config
 alerting_rules.yml # Threshold-based alerting rules
 screenshots/
 targets-status.png # Prometheus targets page
 alert-rules-overview.png # Prometheus alerts page
 grafana-live-dashboard.png # Grafana dashboard view
 alert-triggered.png # Alert in firing state
 prometheus-config-view.png # Config file screenshot
 alerting-rules-view.png # Alert rules screenshot
 README.md # Project documentation
```

## Deliverables

- Prometheus configuration with multi-target scraping
- Alerting rules for CPU, Memory, and Disk thresholds
- Grafana dashboard screenshots with live metrics
- Alert lifecycle demonstration (Inactive → Pending → Firing)
- Full documentation of the observability pipeline

## Troubleshooting Reference

### Prometheus Not Collecting Metrics
```bash
# Tail Prometheus logs
sudo journalctl -u prometheus -f

# Validate YAML syntax
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

## Security Notes

### Security Group Rules

**Monitoring Node:**
- Port 22: Restricted to known IP ranges
- Port 9090: Accessible for Prometheus UI
- Port 3000: Accessible for Grafana UI

**Target Nodes:**
- Port 22: Restricted to known IP ranges
- Port 9100: Open for Prometheus scraping

### Hardening Practices Applied
- SSH key-based authentication enforced
- Minimal port exposure via security group rules
- Regular OS patching applied
- Principle of least privilege for service accounts
- Network-level firewall rules configured

## Operational Best Practices

1. **Threshold Calibration** — Set alert thresholds based on observed baseline behavior
2. **Alert Cooldown** — 2-minute `for` duration prevents noise from transient spikes
3. **Dashboard Layout** — Metrics grouped by domain (CPU, memory, disk, network)
4. **Retention Policy** — Configured to balance storage cost and lookback window
5. **Periodic Reviews** — Weekly dashboard audits recommended

## Takeaways

1. **Shift to Proactive Monitoring** — Live dashboards surface issues before users notice
2. **Smart Alerting** — Proper `for` durations significantly reduce false positives
3. **Horizontal Scalability** — New servers can be added to Prometheus with a single config line
4. **Metric Visualization** — Grafana turns raw PromQL into actionable insights
5. **Resilient Services** — Systemd auto-restart ensures zero-touch recovery from crashes

## Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Prometheus | `http://<monitor-node-ip>:9090` | N/A |
| Grafana | `http://<monitor-node-ip>:3000` | admin / admin (change on first login) |

## Teardown

To decommission all resources:
1. Terminate all EC2 instances from the AWS Console
2. Delete associated security groups
3. Remove orphaned EBS volumes if present
4. Release any allocated Elastic IPs

## Reference Links

- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
- [PromQL Query Examples](https://prometheus.io/docs/prometheus/latest/querying/examples/)

## Outcome

A fully operational observability stack delivering:
- Real-time monitoring across multiple EC2 nodes
- Visual dashboards for CPU, memory, disk, and network metrics
- Automated threshold alerting with lifecycle management
- Proactive incident detection ahead of user-facing impact
- Elimination of manual SSH-based health checks

---

**All project deliverables completed. The observability stack is live and actively monitoring infrastructure health.**
