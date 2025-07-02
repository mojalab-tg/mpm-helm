#!/bin/bash

# HAProxy Secrets Generation Script
# This script helps generate manual secrets for HAProxy when cert-manager is not available

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="default"
RELEASE_NAME="haproxy"
DOMAINS=("moov-portal.mojalab.gouv.tg" "moov-vault.mojalab.gouv.tg" "moov-sdk.mojalab.gouv.tg" "moov-mcc.mojalab.gouv.tg")
CERT_DAYS=365

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
HAProxy Manual Secrets Generation Script

Usage: $0 [OPTIONS]

Options:
    -n, --namespace NAMESPACE    Kubernetes namespace (default: default)
    -r, --release RELEASE        Helm release name (default: haproxy)
    -d, --domains DOMAINS        Comma-separated list of domains (default: moov-portal.mojalab.gouv.tg,moov-vault.mojalab.gouv.tg,moov-sdk.mojalab.gouv.tg,moov-mcc.mojalab.gouv.tg)
    -c, --cert-days DAYS         Certificate validity in days (default: 365)
    -h, --help                   Show this help message

Examples:
    # Generate secrets with default values
    $0

    # Generate secrets for specific namespace and release
    $0 -n my-namespace -r my-haproxy

    # Generate secrets with custom domains
    $0 -d "my-domain.com,api.my-domain.com"

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -d|--domains)
            IFS=',' read -ra DOMAINS <<< "$2"
            shift 2
            ;;
        -c|--cert-days)
            CERT_DAYS="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

print_info "Generating HAProxy manual secrets for release: $RELEASE_NAME in namespace: $NAMESPACE"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    print_error "openssl is not installed or not in PATH"
    exit 1
fi

# Create temporary directory for certificates
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_info "Creating temporary directory: $TEMP_DIR"

# Generate SSL certificate and private key
print_info "Generating SSL certificate for domains: ${DOMAINS[*]}"

# Create private key
openssl genrsa -out "$TEMP_DIR/private.key" 2048

# Create certificate signing request with multiple domains
DOMAIN_LIST=""
for domain in "${DOMAINS[@]}"; do
    if [ -z "$DOMAIN_LIST" ]; then
        DOMAIN_LIST="$domain"
    else
        DOMAIN_LIST="$DOMAIN_LIST, DNS:$domain"
    fi
done

# Create OpenSSL config for multiple domains
cat > "$TEMP_DIR/openssl.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = TG
ST = Lome
L = Lome
O = Mojaloop
OU = Payment Manager
CN = ${DOMAINS[0]}

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAINS[0]}
EOF

# Add additional domains to config
for i in "${!DOMAINS[@]}"; do
    if [ $i -gt 0 ]; then
        echo "DNS.$((i+1)) = ${DOMAINS[$i]}" >> "$TEMP_DIR/openssl.conf"
    fi
done

# Create certificate signing request
openssl req -new -key "$TEMP_DIR/private.key" -out "$TEMP_DIR/cert.csr" -config "$TEMP_DIR/openssl.conf"

# Create self-signed certificate
openssl x509 -req -in "$TEMP_DIR/cert.csr" -signkey "$TEMP_DIR/private.key" -out "$TEMP_DIR/cert.crt" -days "$CERT_DAYS" -extensions v3_req -extfile "$TEMP_DIR/openssl.conf"

# Create combined PEM file for HAProxy
cat "$TEMP_DIR/cert.crt" "$TEMP_DIR/private.key" > "$TEMP_DIR/haproxy.pem"

# Generate random passwords
STATS_PASSWORD=$(openssl rand -base64 32)
ADMIN_PASSWORD=$(openssl rand -base64 32)

print_info "Generated random passwords for HAProxy services"

# Create Kubernetes secrets
print_info "Creating Kubernetes secrets in namespace: $NAMESPACE"

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create TLS bundle secret for HAProxy
kubectl create secret generic "$RELEASE_NAME-tls-bundle" \
    --from-file=haproxy.pem="$TEMP_DIR/haproxy.pem" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create stats credentials secret
kubectl create secret generic "$RELEASE_NAME-stats" \
    --from-literal=username=admin \
    --from-literal=password="$STATS_PASSWORD" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create admin credentials secret
kubectl create secret generic "$RELEASE_NAME-admin" \
    --from-literal=password="$ADMIN_PASSWORD" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

print_success "All secrets created successfully!"

# Create values file with manual secrets configuration
VALUES_FILE="$TEMP_DIR/haproxy-manual-secrets-values.yaml"

cat > "$VALUES_FILE" << EOF
# HAProxy Manual Secrets Configuration
# Generated on $(date)
# Domains: ${DOMAINS[*]}
# Release: $RELEASE_NAME
# Namespace: $NAMESPACE

# Disable cert-manager and enable manual secrets
certificates:
  certManager:
    enabled: false

secrets:
  enabled: true
  name: "$RELEASE_NAME-secrets"
  ssl:
    certificate: "$(base64 -w 0 < "$TEMP_DIR/cert.crt")"
    privateKey: "$(base64 -w 0 < "$TEMP_DIR/private.key")"
    caCertificate: ""

haproxy:
  stats:
    enabled: true
    port: 8404
    username: "admin"
    password: "$STATS_PASSWORD"
  admin:
    password: "$ADMIN_PASSWORD"
EOF

print_info "Created values file with manual secrets configuration: $VALUES_FILE"
print_info "You can use this file with: helm install $RELEASE_NAME ./haproxy -f $VALUES_FILE -n $NAMESPACE"

# Display secret information
cat << EOF

${GREEN}=== HAProxy Manual Secrets Generated Successfully ===${NC}

${BLUE}Release Name:${NC} $RELEASE_NAME
${BLUE}Namespace:${NC} $NAMESPACE
${BLUE}Domains:${NC} ${DOMAINS[*]}
${BLUE}Certificate Validity:${NC} $CERT_DAYS days

${BLUE}Generated Secrets:${NC}
- $RELEASE_NAME-tls-bundle (HAProxy PEM bundle)
- $RELEASE_NAME-stats (Stats credentials)
- $RELEASE_NAME-admin (Admin credentials)

${BLUE}Credentials:${NC}
- Stats Username: admin
- Stats Password: $STATS_PASSWORD
- Admin Password: $ADMIN_PASSWORD

${YELLOW}Important:${NC}
- This uses self-signed certificates for development/testing
- For production, consider using cert-manager with Let's Encrypt
- Store these credentials securely
- The certificate includes all specified domains

${BLUE}Next Steps:${NC}
1. Review the generated values file: $VALUES_FILE
2. Customize the HAProxy configuration in values.yaml
3. Deploy with: helm install $RELEASE_NAME ./haproxy -f $VALUES_FILE -n $NAMESPACE

${BLUE}To use cert-manager instead:${NC}
1. Set certificates.certManager.enabled: true
2. Set secrets.enabled: false
3. Ensure cert-manager is installed in your cluster

EOF

print_success "Manual secret generation completed!" 