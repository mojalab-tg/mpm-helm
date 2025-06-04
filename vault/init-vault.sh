#!/bin/bash
# Quick Vault initialization script
# Usage: ./quick-init.sh [namespace] [release-name]

set -e

NAMESPACE="${1:-default}"
RELEASE="${2:-vault}"
POD_NAME="${RELEASE}-vault-0"

echo "========================================"
echo "🚀 Quick Vault Initialization"
echo "========================================"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE"
echo "Pod name: $POD_NAME"
echo "========================================"

# Check if pod exists
echo "Checking if Vault pod exists..."
if ! kubectl get pod -n $NAMESPACE $POD_NAME >/dev/null 2>&1; then
  echo "❌ Pod $POD_NAME not found in namespace $NAMESPACE"
  echo ""
  echo "Available pods in namespace $NAMESPACE:"
  kubectl get pods -n $NAMESPACE
  exit 1
fi

echo "✅ Pod $POD_NAME found"

# Check if already initialized
echo "Checking Vault initialization status..."
if kubectl exec -n $NAMESPACE $POD_NAME -- vault status -format=json 2>/dev/null | grep '"initialized":true' >/dev/null; then
  echo "✅ Vault is already initialized"
  echo ""
  echo "Current Vault status:"
  kubectl exec -n $NAMESPACE $POD_NAME -- vault status
  exit 0
fi

echo "📝 Vault is not initialized yet, proceeding with initialization..."

# Initialize Vault
echo "🔧 Initializing Vault..."
kubectl exec -n $NAMESPACE $POD_NAME -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > /tmp/vault-keys-${RELEASE}.json

echo "✅ Vault initialization completed"

# Extract root token and unseal keys using Method 1
echo "🔍 Extracting keys from initialization output..."

# Extract root token
ROOT_TOKEN=$(grep '"root_token"' /tmp/vault-keys-${RELEASE}.json | sed 's/.*"root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Extract exactly 5 unseal keys using Method 1 (verified working)
echo "Extracting exactly 5 unseal keys..."
grep -A 100 '"unseal_keys_b64"' /tmp/vault-keys-${RELEASE}.json | \
  grep -B 100 ']' | \
  grep -oE '"[A-Za-z0-9+/]{40,}={0,2}"' | \
  sed 's/"//g' | \
  head -n 5 > /tmp/unseal-keys-${RELEASE}.txt

# Debug output
echo "Debug - Extracted:"
echo "  Root token: ${ROOT_TOKEN:0:20}..."
echo "  Unseal keys:"
cat /tmp/unseal-keys-${RELEASE}.txt | nl
echo "  Expected: 5 keys, Got: $(wc -l < /tmp/unseal-keys-${RELEASE}.txt) keys"

# Validate extraction
if [ -z "$ROOT_TOKEN" ] || [ ! -s /tmp/unseal-keys-${RELEASE}.txt ]; then
  echo "❌ Failed to extract keys from JSON"
  echo "Raw JSON output:"
  cat /tmp/vault-keys-${RELEASE}.json
  echo ""
  echo "Unseal keys file content:"
  cat /tmp/unseal-keys-${RELEASE}.txt
  exit 1
fi

UNSEAL_COUNT=$(wc -l < /tmp/unseal-keys-${RELEASE}.txt)
echo "✅ Successfully extracted:"
echo "  - Root token: ${ROOT_TOKEN:0:10}..."
echo "  - Unseal keys: $UNSEAL_COUNT keys"

# Create Kubernetes secret
echo "📝 Creating Kubernetes secret..."
SECRET_NAME="${RELEASE}-vault-keys"
SECRET_ARGS="--from-literal=root-token=$ROOT_TOKEN"

# Add unseal keys to secret (limit to first 5 keys)
INDEX=0
while read -r KEY && [ $INDEX -lt 5 ]; do
  SECRET_ARGS="$SECRET_ARGS --from-literal=unseal-key-$INDEX=$KEY"
  INDEX=$((INDEX + 1))
done < /tmp/unseal-keys-${RELEASE}.txt

if kubectl create secret generic -n $NAMESPACE $SECRET_NAME $SECRET_ARGS; then
  echo "✅ Secret '$SECRET_NAME' created successfully"
else
  echo "❌ Failed to create secret '$SECRET_NAME'"
  exit 1
fi

# Unseal Vault
echo "🔓 Unsealing Vault (using first 3 keys)..."
INDEX=0
SUCCESSFUL_UNSEALS=0
while read -r KEY && [ $INDEX -lt 3 ]; do
  echo "  Applying unseal key $((INDEX + 1))/3..."
  if kubectl exec -n $NAMESPACE $POD_NAME -- vault operator unseal "$KEY" >/dev/null 2>&1; then
    echo "  ✅ Key $((INDEX + 1)) applied successfully"
    SUCCESSFUL_UNSEALS=$((SUCCESSFUL_UNSEALS + 1))
  else
    echo "  ⚠️ Warning: Failed to apply key $((INDEX + 1))"
  fi
  INDEX=$((INDEX + 1))
done < /tmp/unseal-keys-${RELEASE}.txt

echo "✅ Applied $SUCCESSFUL_UNSEALS/3 unseal keys"

# Verify final status
echo ""
echo "🔍 Final Vault status:"
kubectl exec -n $NAMESPACE $POD_NAME -- vault status

echo ""
echo "========================================"
echo "🎉 Initialization Summary"
echo "========================================"
echo "✅ Vault initialized successfully"
echo "✅ Secret created: $SECRET_NAME"
echo "✅ Root token: ${ROOT_TOKEN:0:10}..."
echo "✅ Backup file: /tmp/vault-keys-${RELEASE}.json"
echo ""
echo "⚠️  Important:"
echo "   - Store the root token securely"
echo "   - Backup the keys file"
echo "   - Consider setting up auth methods"
echo "========================================"