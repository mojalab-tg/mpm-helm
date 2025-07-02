#!/usr/bin/env sh

set -ex

DOMAIN="${VAULT_DOMAIN:-mojalab.gouv.tg}"

I would like to add this script to the vault-unseealin a way that it run after unseal: 

enable_app_role_auth() {
  vault auth enable approle
  vault write auth/approle/role/my-role secret_id_ttl=1000m token_ttl=1000m token_max_ttl=1000m
  echo "app role is enabled"
}

generate_secret_id() {
  vault read -field role_id auth/approle/role/my-role/role-id > /vault/shared/tmp/role-id
  vault write -field secret_id -f auth/approle/role/my-role/secret-id > /vault/shared/secret-id
  echo "role-id and secret-id are generated into /vault/shared/"
}

populate_data() {
  vault secrets enable -path=pki pki
  vault secrets enable -path=secrets kv
  vault secrets tune -max-lease-ttl=97600h pki
  vault write -field=certificate pki/root/generate/internal \
          common_name="${DOMAIN}" \
          ttl=97600h
  vault write pki/config/urls \
      issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
      crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
  vault write pki/roles/${DOMAIN} allowed_domains=${DOMAIN} allow_subdomains=true allow_any_name=true allow_localhost=true enforce_hostnames=false require_cn=false max_ttl=97600h
  vault write pki/roles/client-cert-role allowed_domains=${DOMAIN} allow_subdomains=true allow_any_name=true allow_localhost=true enforce_hostnames=false require_cn=false max_ttl=97600h
  vault write pki/roles/server-cert-role allowed_domains=${DOMAIN} allow_subdomains=true allow_any_name=true allow_localhost=true enforce_hostnames=false require_cn=false max_ttl=97600h

  tee policy.hcl <<EOF
# List, create, update, and delete key/value secrets
path "secrets/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "kv/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "pki/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "pki_int/*"
{
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

  vault policy write test-policy policy.hcl
  vault write auth/approle/role/my-role policies=test-policy ttl=1h

  vault secrets enable -path=pki_int pki
  vault secrets tune -max-lease-ttl=43800h pki_int
  vault write pki_int/roles/${DOMAIN} allowed_domains=${DOMAIN} allow_subdomains=true allow_any_name=true allow_localhost=true enforce_hostnames=false max_ttl=600h

  echo "Data population done sucess fully"
}

if [ -s /vault/shared/tmp/role-id ]; then
  echo "Vault is ready for MPM"
else
  echo "Getting vault ready for MPM"
  enable_app_role_auth
  generate_secret_id
  populate_data
fi