# DNS Configuration Guide for gateway.infocarenepal.com

## Problem
Your Traefik container is failing to obtain an SSL certificate because DNS validation is failing with this error:
```
propagation: time limit exceeded: last error: authoritative nameservers: NS ns1.digitalocean.com.:53 returned NXDOMAIN for _acme-challenge.gateway.infocarenepal.com.
```

## Root Cause
The DNS record `_acme-challenge.gateway.infocarenepal.com` does not exist or is not properly propagated.

## Solution Steps

### Step 1: Verify Your Domain DNS Setup
1. Go to [DigitalOcean Control Panel](https://cloud.digitalocean.com/networking/domains)
2. Check if `infocarenepal.com` is registered in DigitalOcean
3. Verify the nameservers are set to:
   - ns1.digitalocean.com
   - ns2.digitalocean.com
   - ns3.digitalocean.com

### Step 2: Add DNS Records in DigitalOcean
You need to add a DNS A record for the subdomain:

1. In DigitalOcean DNS management for `infocarenepal.com`:
2. Add an **A Record**:
   - Type: A
   - Name: gateway
   - Value: {YOUR_SERVER_IP_ADDRESS}
   - TTL: 3600 (or default)

3. Wait 5-10 minutes for DNS propagation

### Step 3: Verify DNS Resolution
Run this command on your server to verify:
```bash
nslookup gateway.infocarenepal.com 8.8.8.8
```

You should see output like:
```
Server:         8.8.8.8
Address:        8.8.8.8#53

Non-authoritative answer:
Name:   gateway.infocarenepal.com
Address: {YOUR_SERVER_IP}
```

### Step 4: Verify DigitalOcean API Token
Make sure your `DO_API_TOKEN` in `.env` is correct and has permissions:
- Read and write access to DNS records
- Domain management access

Test it:
```bash
curl -X GET "https://api.digitalocean.com/v2/domains/infocarenepal.com" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer dop_v1_YOUR_TOKEN"
```

### Step 5: Check Traefik Configuration
Your current setup uses DigitalOcean DNS challenge. Verify environment variables:
```bash
docker-compose config | grep -A 20 "main:"
```

### Step 6: Restart and Test
Once DNS is properly configured:

1. Remove the staging server line from `compose.yaml`
2. Clear ACME cache: `docker volume rm api_gateway_acme`
3. Restart: `docker-compose up -d`
4. Check logs: `docker-compose logs -f main`

## Alternative: If DNS Challenge Keeps Failing

If DNS challenge continues to fail, you can use HTTP challenge instead:

Replace in `compose.yaml`:
```yaml
- --certificatesresolvers.letsencrypt.acme.dnschallenge=true
- --certificatesresolvers.letsencrypt.acme.dnschallenge.provider=digitalocean
- --certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,8.8.8.8:53
```

With:
```yaml
- --certificatesresolvers.letsencrypt.acme.httpchallenge=true
- --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http
```

**Note**: HTTP challenge requires port 80 to be accessible from the internet.

## Debugging Commands

```bash
# Check if DNS records exist
dig gateway.infocarenepal.com @ns1.digitalocean.com

# Check DigitalOcean DNS configuration
curl -X GET "https://api.digitalocean.com/v2/domains/infocarenepal.com/records" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Watch logs in real-time
docker-compose logs -f main

# Check certificate status
docker exec api_gateway-main-1 ls -la /letsencrypt/
```

## Current Status
- ✅ Traefik updated to `traefik:latest`
- ✅ Staging server enabled for testing (change back when DNS is working)
- ⏳ Waiting for DNS configuration
