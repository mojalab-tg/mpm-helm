#!/bin/bash
# Vault Initialization Debug Helper Script
# This script helps debug Vault initialization issues

echo "=========================================="
echo "🔍 Vault Initialization Debug Helper"
echo "=========================================="

NAMESPACE="${1:-default}"
RELEASE_NAME="${2:-vault}"

echo "Using namespace: $NAMESPACE"
echo "Using release name: $RELEASE_NAME"

echo ""
echo "1. Checking Helm release status..."
helm list -n $NAMESPACE
echo ""
helm status $RELEASE_NAME -n $NAMESPACE

echo ""
echo "2. Checking for initialization job..."
kubectl get jobs -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME

echo ""
echo "3. Checking job pods..."
kubectl get pods -n $NAMESPACE -l job-name=${RELEASE_NAME}-init

echo ""
echo "4. Checking recent events..."
kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -10

echo ""
echo "5. Checking vault pods..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o wide

echo ""
echo "6. Checking vault service..."
kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=vault

echo ""
echo "7. Checking secrets..."
kubectl get secrets -n $NAMESPACE | grep vault

echo ""
echo "8. Checking if init job logs are available..."
if kubectl get pods -n $NAMESPACE -l job-name=${RELEASE_NAME}-init | grep -q ${RELEASE_NAME}-init; then
    echo "Found init job pod, showing logs:"
    echo "----------------------------------------"
    kubectl logs -n $NAMESPACE -l job-name=${RELEASE_NAME}-init --tail=50
else
    echo "No init job pod found"
fi

echo ""
echo "9. Checking vault container logs..."
VAULT_POD_NAME="${RELEASE_NAME}-0"
if kubectl get pods -n $NAMESPACE $VAULT_POD_NAME >/dev/null 2>&1; then
    echo "Vault main container logs:"
    echo "----------------------------------------"
    kubectl logs -n $NAMESPACE $VAULT_POD_NAME -c vault --tail=20
    
    echo ""
    echo "Vault unsealer container logs:"
    echo "----------------------------------------"
    kubectl logs -n $NAMESPACE $VAULT_POD_NAME -c vault-unsealer --tail=20
else
    echo "No $VAULT_POD_NAME pod found"
    echo "Available pods:"
    kubectl get pods -n $NAMESPACE
fi

echo ""
echo "=========================================="
echo "🔧 Manual initialization commands:"
echo "=========================================="
echo "If auto-init failed, you can run these commands manually:"
echo ""
echo "# 1. Initialize Vault manually:"
echo "kubectl exec -it -n $NAMESPACE $VAULT_POD_NAME -- vault operator init -key-shares=5 -key-threshold=3 -format=json > /tmp/vault-keys.json"
echo ""
echo "# 2. Create secret manually:"
echo "ROOT_TOKEN=\$(cat /tmp/vault-keys.json | jq -r .root_token)"
echo "kubectl create secret generic -n $NAMESPACE $RELEASE_NAME-keys \\"
echo "  --from-literal=root-token=\"\$ROOT_TOKEN\" \\"
echo "  --from-literal=unseal-key-0=\$(cat /tmp/vault-keys.json | jq -r .unseal_keys_b64[0]) \\"
echo "  --from-literal=unseal-key-1=\$(cat /tmp/vault-keys.json | jq -r .unseal_keys_b64[1]) \\"
echo "  --from-literal=unseal-key-2=\$(cat /tmp/vault-keys.json | jq -r .unseal_keys_b64[2])"
echo ""
echo "# 3. Unseal manually:"
echo "for i in {0..2}; do"
echo "  kubectl exec -it -n $NAMESPACE $VAULT_POD_NAME -- vault operator unseal \$(cat /tmp/vault-keys.json | jq -r .unseal_keys_b64[\$i])"
echo "done"

echo ""
echo "=========================================="
echo "🎯 Quick checks:"
echo "=========================================="

# Quick status check
echo "Vault status:"
if kubectl exec -n $NAMESPACE $VAULT_POD_NAME -- vault status 2>/dev/null; then
    echo "✅ Vault is accessible"
else
    echo "❌ Vault is not accessible or not ready"
fi

echo ""
echo "Secret status:"
if kubectl get secret -n $NAMESPACE $RELEASE_NAME-keys >/dev/null 2>&1; then
    echo "✅ $RELEASE_NAME-keys secret exists"
else
    echo "❌ $RELEASE_NAME-keys secret does not exist"
fi

echo ""
echo "=========================================="
echo "Debug completed!"
echo "=========================================="