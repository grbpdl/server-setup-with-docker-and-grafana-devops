# Server Deployment Setup Guide for New Droplet

This document provides a complete guide to replicate the current server setup on a new DigitalOcean droplet.

## Current Setup Overview

Your existing infrastructure consists of:

1. **API Gateway (Traefik)** - Reverse proxy with SSL/TLS termination
2. **Monitoring Stack** - Prometheus, Grafana, cAdvisor, Node Exporter
3. **Container Management** - Portainer for Docker management
4. **Message Queue** - RabbitMQ (referenced in dynamic config)

---

## Prerequisites

### 1. Create a New DigitalOcean Droplet

- **Recommended OS**: Ubuntu 22.04 LTS or Ubuntu 24.04 LTS
- **Recommended Size**: At least 2GB RAM / 2vCPU (adjust based on workload)
- **Region**: Choose based on proximity to users

### 2. Initial Server Setup

```bash
# Update system packages
sudo apt update
sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installations
docker --version
docker-compose --version

# Add current user to docker group (optional, for non-sudo access)
sudo usermod -aG docker $USER
```

### 3. Configure IP Addresses & Networking

#### 3.1 Identify Your Droplet IP

After creating the droplet on DigitalOcean:

```bash
# Your droplet IP is shown in the DigitalOcean dashboard
# Also check via command line:
curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address

# Or simply run:
hostname -I
ip addr show
```

**Record this IP** - You'll need it for DNS and firewall configuration.

#### 3.2 Enable Private Networking (Optional but Recommended)

If you plan to scale to multiple droplets:

1. Go to **DigitalOcean Dashboard → Networking → Private Networks**
2. Create a private network in the same region
3. Attach your droplet to it
4. Use private IP for inter-droplet communication

**Private IP Benefits**:

- Secure communication between droplets
- No bandwidth charges for internal traffic
- Reduced exposure if one droplet is compromised

### 4. Configure Firewall (UFW - Ubuntu Firewall)

**This is CRITICAL for security!** By default, all ports are open. Restrict access immediately.

#### 4.1 Enable UFW and Allow Essential Ports

```bash
# Enable UFW
sudo ufw enable

# Verify status
sudo ufw status verbose

# Allow SSH (CRITICAL - do this first!)
sudo ufw allow 22/tcp

# Allow HTTP (needed for Let's Encrypt validation)
sudo ufw allow 80/tcp

# Allow HTTPS (your main traffic)
sudo ufw allow 443/tcp

# Optional: Allow RabbitMQ if external connections needed
# sudo ufw allow 5672/tcp

# View all rules
sudo ufw status numbered
```

#### 4.2 Additional Security Rules (Recommended)

```bash
# Limit SSH connections (prevent brute force)
sudo ufw limit 22/tcp

# Allow Portainer HTTPS only from specific IPs (optional)
# sudo ufw allow from YOUR_IP to any port 9443

# Deny all other incoming traffic (already default)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Check final configuration
sudo ufw status verbose
```

#### 4.3 DigitalOcean Cloud Firewall (Additional Layer)

For extra security, also configure DigitalOcean's built-in firewall:

1. Go to **DigitalOcean Dashboard → Networking → Firewalls**
2. Create new firewall with these inbound rules:
   - SSH: Port 22 (TCP) - Your IP or 0.0.0.0/0
   - HTTP: Port 80 (TCP) - 0.0.0.0/0 (for Let's Encrypt)
   - HTTPS: Port 443 (TCP) - 0.0.0.0/0 (main traffic)
   - RabbitMQ: Port 5672 (TCP) - Your office/home IP only
   - Portainer: Port 9443 (TCP) - Your IP only (behind Traefik usually)

3. Set outbound rules:
   - All TCP: 0.0.0.0/0 (allow outbound)
   - All UDP: 0.0.0.0/0 (allow outbound)

4. Attach firewall to your droplet

#### 4.4 Verify Firewall Rules

```bash
# Check UFW rules
sudo ufw show added

# Test port connectivity from another machine
nc -zv your-droplet-ip 80
nc -zv your-droplet-ip 443

# Or use telnet
telnet your-droplet-ip 443
```

---

## Step-by-Step Setup Instructions

### Step 1: Create Directory Structure

```bash
# Create the main setup directory
mkdir -p ~/docker_setup
cd ~/docker_setup

# Create subdirectories for each service
mkdir -p api_gateway
mkdir -p monitoring
mkdir -p portainer

# Create shared data directories
mkdir -p shared_volumes/prometheus_data
mkdir -p shared_volumes/grafana_data
mkdir -p shared_volumes/portainer_data
```

### Step 2: Create the Production Network

This network is shared by all services:

```bash
docker network create production_network
```

Verify:

```bash
docker network ls | grep production_network
```

### Step 3: Set Up API Gateway (Traefik)

**Location**: `api_gateway/`

#### 3.1 Create `.env` file

**File**: `api_gateway/.env`

```properties
# Your email for Let's Encrypt certificate registration
ACME_EMAIL=your-email@yourdomain.com

# DigitalOcean API Token for DNS challenge
# Get this from: https://cloud.digitalocean.com/account/api/tokens
DO_API_TOKEN=dop_v1_YOUR_API_TOKEN_HERE

# Your domain name for the Traefik dashboard
HOST_NAME=gateway.yourdomain.com

# Traefik image version
TRAEFIK_IMAGE=traefik:v3.0
```

#### 3.2 Create `.htpasswd` file for Basic Auth

Generate the .htpasswd file for dashboard authentication:

```bash
# Install apache2-utils if not present
sudo apt install apache2-utils -y

# Generate .htpasswd (replace 'admin' with desired username)
htpasswd -c api_gateway/.htpasswd admin
# You'll be prompted to enter a password

# Verify the file was created
cat api_gateway/.htpasswd
```

#### 3.3 Create `compose.yaml`

**File**: `api_gateway/compose.yaml`

Copy from your existing setup:
[See full file in api_gateway/compose.yaml]

#### 3.4 Create Dynamic RabbitMQ Config

**File**: `api_gateway/dynamic-rabbitmq.yaml`

Copy from your existing setup for RabbitMQ TCP routing.

#### 3.5 Start the API Gateway

```bash
cd api_gateway
docker-compose up -d
```

Check logs:

```bash
docker-compose logs -f main
```

### Step 4: Set Up Monitoring Stack

**Location**: `monitoring/`

#### 4.1 Create `docker-compose.yml`

**File**: `monitoring/docker-compose.yml`

Copy from your existing setup.

#### 4.2 Create `prometheus.yml`

**File**: `monitoring/prometheus.yml`

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]

  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]
```

#### 4.3 Start Monitoring Stack

```bash
cd monitoring
docker-compose up -d
```

Check logs:

```bash
docker-compose logs -f
```

### Step 5: Set Up Portainer (Container Management)

**Location**: `portainer/`

#### 5.1 Create `docker-compose.yaml`

**File**: `portainer/docker-compose.yaml`

Copy from your existing setup.

#### 5.2 Start Portainer

```bash
cd portainer
docker-compose up -d
```

Access Portainer:

- **URL**: https://container.yourdomain.com (or your configured domain)
- **Port**: 9443 (HTTPS)

---

## Required Credentials & Configuration

### 1. **DigitalOcean API Token** ⭐ IMPORTANT

**Where to Get**:

- Navigate to: https://cloud.digitalocean.com/account/api/tokens
- Click "Generate New Token"
- Select scopes: `read` and `write`
- Copy the token (shown only once!)

**Used For**: DNS challenge for Let's Encrypt SSL certificates

**Store In**: `api_gateway/.env` as `DO_API_TOKEN`

### 2. **Domain Names**

You need to configure 3 domain names pointing to your new droplet IP:

- `gateway.yourdomain.com` - Traefik dashboard
- `analytics.yourdomain.com` - Grafana
- `container.yourdomain.com` - Portainer

**How to Configure**:

1. Get your droplet's IP address (see Section 3.1 above)
2. **Wait for Firewall to be configured** (see Section 4 above)
3. In your domain DNS settings, create A records:
   ```
   gateway    A    your-droplet-ip
   analytics  A    your-droplet-ip
   container  A    your-droplet-ip
   ```
4. Verify DNS propagation:

   ```bash
   # Test DNS resolution (may take up to 24 hours, usually faster)
   nslookup gateway.yourdomain.com
   dig gateway.yourdomain.com

   # Once resolved, test connectivity
   ping gateway.yourdomain.com
   curl -I http://gateway.yourdomain.com
   ```

**Note**: DNS propagation can take up to 24 hours but typically resolves within a few minutes. You can use online tools to check propagation status: https://dnschecker.org/

### 3. **Email for Let's Encrypt**

Store in `api_gateway/.env` as `ACME_EMAIL`. Should be a valid email address.

### 4. **Traefik Basic Auth Credentials**

Used for dashboard access. Generated via `.htpasswd` file.

---

## Accessing Services After Setup

### 1. Traefik Dashboard

- **URL**: https://gateway.yourdomain.com
- **Username/Password**: From your `.htpasswd` file
- **Port**: 443 (HTTPS)

### 2. Grafana (Monitoring)

- **URL**: https://analytics.yourdomain.com
- **Default Credentials**: admin / admin
- **Important**: Change default password on first login
- **Port**: 443 (HTTPS)

### 3. Portainer (Container Management)

- **URL**: https://container.yourdomain.com
- **Port**: 443 (HTTPS)
- **Setup**: Initial user creation on first access

---

## Post-Deployment Verification Checklist

- [ ] Production network created
- [ ] All `.env` files configured with correct credentials
- [ ] API Gateway container running: `docker ps | grep traefik`
- [ ] Monitoring stack containers running: `docker ps | grep -E "prometheus|grafana|cadvisor|node-exporter"`
- [ ] Portainer container running: `docker ps | grep portainer`
- [ ] DNS records propagated (test with `nslookup gateway.yourdomain.com`)
- [ ] Traefik dashboard accessible via HTTPS
- [ ] SSL certificate issued (check Traefik logs)
- [ ] Grafana accessible and showing metrics
- [ ] Portainer accessible and docker socket connected

---

## Useful Commands

### Docker Commands

```bash
# View all running containers
docker ps

# View specific service logs
docker logs -f container_name

# Restart a service
docker-compose -f compose.yaml restart service_name

# Rebuild containers
docker-compose -f compose.yaml down && docker-compose -f compose.yaml up -d

# Check network connections
docker network inspect production_network
```

### Traefik Specific

```bash
# View ACME certificate file
cat api_gateway/letsencrypt/acme.json

# Verify Traefik config
docker exec container_name traefik version
```

### System Monitoring

```bash
# View system resource usage
docker stats

# Check disk usage
docker system df
```

---

## Troubleshooting

### ⚠️ Portainer - Page Not Found Error

This is the most common issue. Here's how to fix it:

#### Problem 1: Wrong URL or Subdomain

**Common Mistakes**:

- Accessing `https://container.infocarenepal.com:9443` ❌ (wrong port)
- Accessing `https://portainer.yourdomain.com` ❌ (wrong subdomain)
- Accessing `http://container.infocarenepal.com` ❌ (need HTTPS)

**Solution**: Use the correct URL configured in Traefik labels:

```bash
# Check the configured domain in portainer compose.yaml
grep "Host(" portainer/docker-compose.yaml

# It should be something like:
# https://container.yourdomain.com  (HTTPS only, no port number)
```

#### Problem 2: Portainer Container Not Running

```bash
# Check if Portainer container is actually running
docker ps | grep portainer

# If not running, check the logs
docker logs portainer

# Try to restart it
cd portainer
docker-compose restart

# Or rebuild it
docker-compose down
docker-compose up -d
```

#### Problem 3: Traefik Not Routing to Portainer

**Step 1**: Verify Traefik is running and healthy:

```bash
cd api_gateway
docker-compose ps

# Check Traefik logs for errors
docker-compose logs main | tail -50
```

**Step 2**: Verify Portainer container is on the correct network:

```bash
# Check if portainer is on production_network
docker inspect portainer | grep -A 10 NetworkSettings

# Should show: "production_network" in the networks section
```

**Step 3**: Verify Traefik can see Portainer labels:

```bash
# Check Traefik's docker provider logs
docker logs traefik_container_name | grep -i "portainer\|frontend" | tail -20
```

**Step 4**: Check Traefik dashboard for routes:

```bash
# Access Traefik dashboard (needs basic auth)
# https://gateway.yourdomain.com
# Look for "frontend" router in HTTP Routers section
# Check if it shows "Service: frontend" and status is "success"
```

#### Problem 3: Network Configuration Issue

The issue might be in the `docker-compose.yaml` - the network name mismatch:

```bash
# Check current compose file
cat portainer/docker-compose.yaml

# Look for the network definition
# It might say:
# networks:
#   network:
#     name: production_network
#
# This is correct! ✅
```

If there's a mismatch, you may need to update it:

```yaml
# WRONG - network alias doesn't match:
networks:
  my_network:
    name: production_network

# CORRECT - both internal and external names match:
networks:
  network:
    name: production_network
    external: true
```

#### Complete Portainer Troubleshooting Steps

Run these commands in order:

```bash
# 1. Verify DNS resolution
nslookup container.yourdomain.com
dig container.yourdomain.com

# 2. Test basic connectivity to the IP
ping your-droplet-ip
curl -I http://your-droplet-ip:80

# 3. Check if Traefik is listening on port 443
sudo netstat -tlnp | grep 443
sudo ss -tlnp | grep 443

# 4. Check Traefik logs for certificate and routing
cd api_gateway
docker-compose logs main | grep -i "certificate\|container\|frontend"

# 5. Verify Portainer container status
cd portainer
docker-compose ps
docker logs portainer

# 6. Check network connectivity between containers
docker network inspect production_network

# 7. Verify Traefik sees Portainer via Docker provider
docker exec traefik_name traefik version
docker logs traefik_name | grep -A5 -B5 "frontend\|container"

# 8. Test direct Portainer access (bypassing Traefik)
curl -k https://your-droplet-ip:9443/
# or via browser: https://your-droplet-ip:9443/
```

#### Quick Fix Checklist

- [ ] Firewall allows port 443: `sudo ufw status | grep 443`
- [ ] Firewall allows port 80: `sudo ufw status | grep 80`
- [ ] DNS resolves correctly: `nslookup container.yourdomain.com`
- [ ] Traefik container running: `docker ps | grep traefik`
- [ ] Portainer container running: `docker ps | grep portainer`
- [ ] Both on production_network: `docker network inspect production_network`
- [ ] SSL certificate issued: Check Traefik logs for "Certificate" entries
- [ ] Can access Traefik dashboard: `https://gateway.yourdomain.com`
- [ ] Traefik shows "frontend" router as "success"
- [ ] Try direct IP access: `https://droplet-ip:9443`

#### Alternative Access Methods

If Traefik routing still doesn't work, try these:

```bash
# 1. Direct access via Portainer's HTTPS port
https://your-droplet-ip:9443/

# 2. Access via localhost (if on same server)
https://localhost:9443/

# 3. Forward ports locally and access remotely
ssh -L 9443:localhost:9443 user@your-droplet-ip
# Then access: https://localhost:9443/
```

#### Still Not Working? Debug Mode

Enable debug logging:

```bash
# Check comprehensive Traefik logs
cd api_gateway
docker-compose logs main --follow

# In another terminal, try to access Portainer
# Watch the logs for errors

# Check container resource usage
docker stats portainer

# Verify docker socket permissions
ls -la /var/run/docker.sock
```

---

### SSL Certificate Not Issuing

1. Check DNS resolution: `nslookup yourdomain.com`
2. View Traefik logs: `docker logs traefik_container_name`
3. Verify DO API token has correct permissions
4. Ensure ports 80 and 443 are open in firewall

### Services Not Connecting

1. Verify production_network exists: `docker network ls`
2. Check if containers are on the network: `docker network inspect production_network`
3. Restart all services: `docker-compose down && docker-compose up -d`

### Permission Issues

1. Ensure docker group: `sudo usermod -aG docker $USER`
2. Log out and back in for group changes to take effect

---

## Security Best Practices

1. **Change Traefik Dashboard Password** Regularly
2. **Rotate DigitalOcean API Token** Periodically
3. **Use Strong Passwords** for all services
4. **Enable Firewall Rules** (UFW):
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```
5. **Backup ACME Certificate** (`api_gateway/letsencrypt/acme.json`)
6. **Monitor Logs** regularly for suspicious activity
7. **Keep Docker Updated** regularly

---

## File Structure on New Droplet

```
~/docker_setup/
├── api_gateway/
│   ├── .env                          (CREATE - with credentials)
│   ├── .htpasswd                     (CREATE - with htpasswd tool)
│   ├── compose.yaml                  (COPY from current setup)
│   ├── dynamic-rabbitmq.yaml         (COPY from current setup)
│   └── letsencrypt/                  (AUTO-CREATED by Traefik)
│       └── acme.json
│
├── monitoring/
│   ├── docker-compose.yml            (COPY from current setup)
│   ├── prometheus.yml                (COPY from current setup)
│   └── prometheus_data/              (Volume - auto-created)
│
├── portainer/
│   ├── docker-compose.yaml           (COPY from current setup)
│   └── portainer_data/               (Volume - auto-created)
│
└── shared_volumes/                   (Optional - for centralized storage)
    ├── prometheus_data/
    ├── grafana_data/
    └── portainer_data/
```

---

## Next Steps

**CRITICAL ORDER - Follow these steps in sequence:**

1. ✅ Create new DigitalOcean droplet
2. ✅ **Configure IP & Firewall** (Sections 3-4)
   - Identify droplet IP
   - Enable UFW firewall
   - Allow ports 22, 80, 443
   - Configure DigitalOcean Cloud Firewall
3. ✅ Run initial setup commands (Docker, Docker Compose)
4. ✅ Create directory structure
5. ✅ Gather credentials:
   - DigitalOcean API Token
   - Domain names
   - Email for certificates
6. ✅ Configure DNS records (A records pointing to droplet IP)
7. ✅ Wait for DNS propagation
8. ✅ Configure `.env` files
9. ✅ Generate `.htpasswd` file
10. ✅ Deploy services (Traefik → Monitoring → Portainer)
11. ✅ Verify all services are running
12. ✅ Test SSL certificates and access via HTTPS
13. ✅ Monitor logs for certificate issuance

**Timing Tips**:

- Firewall: 5 minutes
- DNS propagation: 5 minutes to 24 hours (usually faster)
- SSL certificate issuance: 5-10 minutes after DNS resolves
- Full deployment: 30-45 minutes total

---

## Support & Monitoring

- **Traefik Dashboard**: Check certificate status and routing rules
- **Grafana**: Monitor system metrics, CPU, memory, disk usage
- **Portainer**: Manage containers, view logs, manage volumes
- **Prometheus**: Query raw metrics and alerts

---

**Last Updated**: June 2026
**Setup Version**: Docker Compose based with Traefik v3.0
