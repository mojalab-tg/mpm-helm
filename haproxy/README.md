# HAProxy Helm Chart

A production-ready Helm chart for deploying HAProxy load balancer on Kubernetes with support for HTTP, HTTPS, and TCP proxy configurations.

## Features

- **HTTP/HTTPS Load Balancing**: Support for both HTTP and HTTPS traffic with automatic SSL termination
- **TCP Proxy**: Support for TCP-based services
- **SSL/TLS Management**: Integration with cert-manager for automatic certificate management
- **Health Checks**: Built-in health checks and monitoring
- **High Availability**: Pod disruption budgets and horizontal pod autoscaling
- **Monitoring**: Prometheus metrics and ServiceMonitor support
- **Security**: Network policies and security contexts
- **Configuration Management**: ConfigMap-based configuration with raw HAProxy config blocks

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- cert-manager (optional, for SSL certificate management)
- Prometheus Operator (optional, for monitoring)

## Installation

### Basic Installation

```bash
# Add the repository
helm repo add haproxy https://charts.example.com

# Install HAProxy
helm install my-haproxy ./haproxy
```

### Installation with Custom Values

```bash
# Create a custom values file
cat > my-values.yaml << EOF
haproxy:
  config: |
    # Global section
    global
      maxconn 50000
      log stdout format raw local0 info
      user haproxy
      group haproxy
      daemon

    # Defaults section
    defaults
      log global
      mode http
      option httplog
      option dontlognull
      option http-server-close
      option forwardfor except 127.0.0.0/8
      option redispatch
      retries 3
      timeout http-request 10s
      timeout queue 1m
      timeout connect 10s
      timeout client 1m
      timeout server 1m
      timeout http-keep-alive 10s
      timeout check 10s
      maxconn 2000

    # HTTP Frontend
    frontend http_frontend
      bind *:80
      mode http
      default_backend http_backend
      redirect scheme https code 301 if !{ ssl_fc }

    # HTTPS Frontend
    frontend https_frontend
      bind *:443 ssl crt /etc/ssl/certs/haproxy.pem
      mode http
      default_backend https_backend

    # HTTP Backend
    backend http_backend
      mode http
      balance roundrobin
      option httpchk
      http-check expect status 200
      server web1 my-web-service:80 check maxconn 100
      server web2 my-web-service:80 check maxconn 100

    # HTTPS Backend
    backend https_backend
      mode http
      balance roundrobin
      option httpchk
      http-check expect status 200
      server web1-ssl my-web-service:80 check maxconn 100
      server web2-ssl my-web-service:80 check maxconn 100

    # Stats Frontend
    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s

certificates:
  certManager:
    enabled: true
    certificate:
      dnsNames:
        - "haproxy.mydomain.com"
EOF

# Install with custom values
helm install my-haproxy ./haproxy -f my-values.yaml
```

## Certificate Management

The HAProxy chart supports two certificate management approaches:

### Option 1: Cert-Manager (Recommended for Production)

Cert-manager automatically manages SSL certificates using Let's Encrypt or other certificate authorities.

```yaml
certificates:
  certManager:
    enabled: true
    issuer:
      name: "letsencrypt-prod"
      kind: "ClusterIssuer"
    certificate:
      name: "haproxy-tls"
      secretName: "haproxy-tls"
      dnsNames:
        - "moov-portal.mojalab.gouv.tg"
        - "moov-vault.mojalab.gouv.tg"
        - "moov-sdk.mojalab.gouv.tg"
        - "moov-mcc.mojalab.gouv.tg"
      duration: "2160h"
      renewBefore: "360h"

secrets:
  enabled: false  # Disable manual secrets when using cert-manager
```

**Prerequisites:**
- cert-manager installed in your cluster
- A ClusterIssuer configured (e.g., Let's Encrypt)

### Option 2: Manual Secrets (Development/Testing)

For development environments or when cert-manager is not available, you can use manual secrets with self-signed certificates.

```yaml
certificates:
  certManager:
    enabled: false

secrets:
  enabled: true
  name: "haproxy-secrets"
  ssl:
    certificate: ""  # Base64 encoded certificate (optional)
    privateKey: ""   # Base64 encoded private key (optional)
    # If not provided, self-signed certificates will be generated
```

**Generate Manual Secrets:**

Use the provided script to generate self-signed certificates and secrets:

```bash
# Make the script executable
chmod +x haproxy/generate-secrets.sh

# Generate secrets with default domains
./haproxy/generate-secrets.sh

# Generate secrets with custom domains
./haproxy/generate-secrets.sh -d "my-domain.com,api.my-domain.com" -n my-namespace -r my-haproxy
```

The script will:
- Generate self-signed certificates for specified domains
- Create Kubernetes secrets
- Generate a values file for deployment
- Provide credentials for HAProxy stats and admin interfaces

### Certificate Paths

The chart automatically configures the correct certificate paths based on your choice:

- **Cert-manager**: `/etc/ssl/certs/tls.crt` and `/etc/ssl/certs/tls.key`
- **Manual secrets**: `/etc/ssl/certs/haproxy.pem` (combined certificate and key)

## Configuration

### HAProxy Configuration Block

The HAProxy configuration is set as a complete block in the `values.yaml` file under `haproxy.config`. This allows you to write standard HAProxy configuration directly:

```yaml
haproxy:
  config: |
    # Global section
    global
      maxconn 50000
      log stdout format raw local0 info
      chroot /var/lib/haproxy
      stats socket /var/lib/haproxy/stats mode 600 level admin
      stats timeout 2m
      user haproxy
      group haproxy
      daemon
      ssl-default-bind-ciphers EECDH+AESGCM:EDH+AESGCM
      ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
      ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11 no-tls-tickets

    # Defaults section
    defaults
      log global
      mode http
      option httplog
      option dontlognull
      option http-server-close
      option forwardfor except 127.0.0.0/8
      option redispatch
      retries 3
      timeout http-request 10s
      timeout queue 1m
      timeout connect 10s
      timeout client 1m
      timeout server 1m
      timeout http-keep-alive 10s
      timeout check 10s
      maxconn 2000

    # HTTP Frontend
    frontend http_frontend
      bind *:80
      mode http
      default_backend http_backend
      redirect scheme https code 301 if !{ ssl_fc }

    # HTTPS Frontend
    frontend https_frontend
      bind *:443 ssl crt /etc/ssl/certs/haproxy.pem
      mode http
      default_backend https_backend

    # HTTP Backend
    backend http_backend
      mode http
      balance roundrobin
      option httpchk
      http-check expect status 200
      server web1 web-service:80 check maxconn 100
      server web2 web-service:80 check maxconn 100

    # HTTPS Backend
    backend https_backend
      mode http
      balance roundrobin
      option httpchk
      http-check expect status 200
      server web1-ssl web-service:443 check maxconn 100 ssl
      server web2-ssl web-service:443 check maxconn 100 ssl

    # TCP Backend
    backend tcp_backend
      mode tcp
      balance roundrobin
      option tcp-check
      server tcp1 tcp-service:8080 check maxconn 100
      server tcp2 tcp-service:8080 check maxconn 100

    # Stats Frontend
    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s
```

### SSL/TLS Configuration

#### Using cert-manager

```yaml
certificates:
  certManager:
    enabled: true
    issuer:
      name: "letsencrypt-prod"
      kind: "ClusterIssuer"
    certificate:
      name: "haproxy-tls"
      secretName: "haproxy-tls"
      dnsNames:
        - "haproxy.example.com"
```

#### Manual SSL Certificates

```yaml
secrets:
  enabled: true
  name: "haproxy-secrets"
  ssl:
    certificate: "base64-encoded-certificate"
    privateKey: "base64-encoded-private-key"
```

### Service Configuration

```yaml
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
  ports:
    http:
      port: 80
      targetPort: 80
    https:
      port: 443
      targetPort: 443
```

### Monitoring

#### Prometheus ServiceMonitor

```yaml
serviceMonitor:
  enabled: true
  interval: "30s"
  scrapeTimeout: "10s"
  path: "/metrics"
  port: "metrics"
```

#### HAProxy Stats

The stats configuration is included in the main HAProxy config block:

```yaml
haproxy:
  config: |
    # ... other configuration ...
    
    # Stats Frontend
    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s
```

## Usage Examples

### Basic Web Application Load Balancing

```yaml
haproxy:
  config: |
    global
      maxconn 50000
      log stdout format raw local0 info
      user haproxy
      group haproxy
      daemon

    defaults
      log global
      mode http
      option httplog
      option dontlognull
      option http-server-close
      option forwardfor except 127.0.0.0/8
      option redispatch
      retries 3
      timeout http-request 10s
      timeout queue 1m
      timeout connect 10s
      timeout client 1m
      timeout server 1m
      timeout http-keep-alive 10s
      timeout check 10s
      maxconn 2000

    frontend http_frontend
      bind *:80
      mode http
      default_backend web_backend
      redirect scheme https code 301 if !{ ssl_fc }

    frontend https_frontend
      bind *:443 ssl crt /etc/ssl/certs/haproxy.pem
      mode http
      default_backend web_backend

    backend web_backend
      mode http
      balance roundrobin
      option httpchk
      http-check expect status 200
      server web1 web-app:8080 check
      server web2 web-app:8080 check

    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s
```

### API Gateway Configuration

```yaml
haproxy:
  config: |
    global
      maxconn 50000
      log stdout format raw local0 info
      user haproxy
      group haproxy
      daemon

    defaults
      log global
      mode http
      option httplog
      option dontlognull
      option http-server-close
      option forwardfor except 127.0.0.0/8
      option redispatch
      retries 3
      timeout http-request 10s
      timeout queue 1m
      timeout connect 10s
      timeout client 1m
      timeout server 1m
      timeout http-keep-alive 10s
      timeout check 10s
      maxconn 2000

    frontend api_frontend
      bind *:8080
      mode http
      default_backend api_backend

    backend api_backend
      mode http
      balance leastconn
      option httpchk
      http-check expect status 200
      server api1 api-service:3000 check
      server api2 api-service:3000 check

    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s
```

### TCP Proxy for Database

```yaml
haproxy:
  config: |
    global
      maxconn 50000
      log stdout format raw local0 info
      user haproxy
      group haproxy
      daemon

    defaults
      log global
      mode tcp
      option tcplog
      option dontlognull
      retries 3
      timeout connect 10s
      timeout client 1m
      timeout server 1m
      maxconn 2000

    frontend db_frontend
      bind *:3306
      mode tcp
      default_backend db_backend

    backend db_backend
      mode tcp
      balance roundrobin
      option tcp-check
      server db1 mysql-primary:3306 check
      server db2 mysql-secondary:3306 check

    frontend stats
      bind *:8404
      mode http
      stats uri /stats
      stats realm HAProxy\ Statistics
      stats auth admin:admin123
      stats refresh 10s
```

## Security

### Network Policies

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: "default"
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 443
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 53
```

### Security Context

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
```

## Scaling

### Horizontal Pod Autoscaler

```yaml
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 70
```

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
  maxUnavailable: 1
```

## Troubleshooting

### Check HAProxy Configuration

```bash
# View the generated configuration
kubectl get configmap my-haproxy-config -o yaml

# Check configuration syntax
kubectl exec -it deployment/my-haproxy -- haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

### View Logs

```bash
# View HAProxy logs
kubectl logs -f deployment/my-haproxy

# View logs from a specific pod
kubectl logs -f pod/my-haproxy-xyz123
```

### Check Certificate Status

```bash
# If using cert-manager
kubectl get certificate haproxy-tls
kubectl describe certificate haproxy-tls
```

### Access HAProxy Stats

```bash
# Port forward to stats page
kubectl port-forward svc/my-haproxy 8404:8404

# Access at http://localhost:8404/stats
# Username: admin
# Password: admin123
```

## Values Reference

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of HAProxy replicas | `2` |
| `image.repository` | HAProxy image repository | `haproxy` |
| `image.tag` | HAProxy image tag | `2.8.0` |
| `service.type` | Service type | `LoadBalancer` |
| `haproxy.config` | Complete HAProxy configuration block | See values.yaml |
| `certificates.certManager.enabled` | Enable cert-manager integration | `true` |
| `serviceMonitor.enabled` | Enable Prometheus monitoring | `false` |

For a complete list of configurable parameters, see the `values.yaml` file.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This chart is licensed under the Apache License 2.0. 