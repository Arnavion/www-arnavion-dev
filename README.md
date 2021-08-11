Source of <https://www.arnavion.dev/>


# Pre-requisites

```sh
zypper in --no-recommends pandoc sassc
```


# Build

```sh
./build.sh
```


# Deploy locally

```sh
python3 -m http.server 8080 -d out
```


# Deploy to Azure

```sh
./build.sh publish
```


# Setup

```sh
# Website
DOMAIN_NAME='www.arnavion.dev'
AZURE_WWW_RESOURCE_GROUP_NAME='arnavion-dev-www'
AZURE_WWW_CDN_PROFILE_NAME='cdn-profile'
AZURE_WWW_CDN_ENDPOINT_NAME='www-arnavion-dev'
AZURE_WWW_STORAGE_ACCOUNT_NAME='wwwarnaviondev'

# KeyVault
AZURE_KEY_VAULT_RESOURCE_GROUP_NAME='arnavion-dev'
AZURE_KEY_VAULT_NAME='arnavion-dev'
AZURE_KEY_VAULT_CERTIFICATE_NAME='star-arnavion-dev'

# LogAnalytics
AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_GROUP_NAME='logs'
AZURE_LOG_ANALYTICS_WORKSPACE_NAME='arnavion-log-analytics'


AZURE_SUBSCRIPTION_ID="$(az account show --query id --output tsv)"


# Create a resource group.
az group create --name "$AZURE_WWW_RESOURCE_GROUP_NAME"


# Create a Storage account for the website.
az storage account create \
    --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --name "$AZURE_WWW_STORAGE_ACCOUNT_NAME" \
    --sku 'Standard_LRS' --https-only --min-tls-version 'TLS1_2' --allow-blob-public-access false

storage_account_web_endpoint="$(
    az storage account show \
        --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --name "$AZURE_WWW_STORAGE_ACCOUNT_NAME" \
        --query 'primaryEndpoints.web' --output tsv |
        sed -Ee 's|^https://(.*)/$|\1|'
)"

AZURE_STORAGE_ACCOUNT_CONNECTION_STRING="$(
    az storage account show-connection-string \
        --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --name "$AZURE_WWW_STORAGE_ACCOUNT_NAME" \
        --query connectionString --output tsv
)"


# Create a CDN.
az cdn profile create \
    --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --name "$AZURE_WWW_CDN_PROFILE_NAME" \
    --sku 'Standard_Microsoft'

az cdn endpoint create \
    --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --profile-name "$AZURE_WWW_CDN_PROFILE_NAME" --name "$AZURE_WWW_CDN_ENDPOINT_NAME" \
    --origin "$storage_account_web_endpoint" \
    --origin-host-header "$storage_account_web_endpoint" \
    --enable-compression \
    --no-http \
    --query-string-caching-behavior 'IgnoreQueryString'

az cdn custom-domain create \
    --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" \
    --profile-name "$AZURE_WWW_CDN_PROFILE_NAME" --endpoint-name "$AZURE_WWW_CDN_ENDPOINT_NAME" --name "${DOMAIN_NAME//./-}" \
    --hostname "$DOMAIN_NAME"


# Create a resource group for the Log Analytics workspace.
az group create --name "$AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_GROUP_NAME"


# Create a Log Analytics workspace.
az monitor log-analytics workspace create \
    --resource-group "$AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_GROUP_NAME" --workspace-name "$AZURE_LOG_ANALYTICS_WORKSPACE_NAME"


# Configure the CDN to log to the Log Analytics workspace.
az monitor diagnostic-settings create \
    --name 'logs' \
    --resource "$(
        az cdn profile show \
            --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" --name "$AZURE_WWW_CDN_PROFILE_NAME" \
            --query id --output tsv
    )" \
    --workspace "$(
        az monitor log-analytics workspace show \
            --resource-group "$AZURE_LOG_ANALYTICS_WORKSPACE_RESOURCE_GROUP_NAME" --workspace-name "$AZURE_LOG_ANALYTICS_WORKSPACE_NAME" \
            --query id --output tsv
    )" \
    --logs '[{ "category": "AzureCdnAccessLog", "enabled": true }]'


# Register the CDN service principal "Microsoft.AzureFrontDoor-Cdn"
az ad sp create --id '205478c0-bd83-4e1b-a9d6-db63a3e1e1c8'


# Create a custom role for the CDN to access the KeyVault.
az role definition create --role-definition "$(
    jq --null-input \
        --arg 'AZURE_ROLE_NAME' 'cdn-custom-domain-https-secret' \
        --arg 'AZURE_SUBSCRIPTION_ID' "$AZURE_SUBSCRIPTION_ID" \
        '{
            "Name": $AZURE_ROLE_NAME,
            "AssignableScopes": [
                "/subscriptions/\($AZURE_SUBSCRIPTION_ID)"
            ],
            "Actions": [],
            "DataActions": [
                "Microsoft.KeyVault/vaults/secrets/getSecret/action"
            ],
        }'
)"


# Apply the role to the CDN
az role assignment create \
    --role 'cdn-custom-domain-https-secret' \
    --assignee "$(az ad sp list --display-name 'Microsoft.AzureFrontDoor-Cdn' --query '[0].objectId' --output tsv)" \
    --scope "$(az keyvault show --name "$AZURE_KEY_VAULT_NAME" --query id --output tsv)/secrets/$AZURE_KEY_VAULT_CERTIFICATE_NAME"


# Enable HTTPS on the CDN
az cdn custom-domain enable-https \
    --resource-group "$AZURE_WWW_RESOURCE_GROUP_NAME" \
    --profile-name "$AZURE_WWW_CDN_PROFILE_NAME" --endpoint-name "$AZURE_WWW_CDN_ENDPOINT_NAME" --name "${DOMAIN_NAME//./-}" \
    --user-cert-subscription-id "$AZURE_SUBSCRIPTION_ID" \
    --user-cert-group-name "$AZURE_KEY_VAULT_RESOURCE_GROUP_NAME" \
    --user-cert-vault-name "$AZURE_KEY_VAULT_NAME" \
    --user-cert-secret-name "$AZURE_KEY_VAULT_CERTIFICATE_NAME" \
    --user-cert-protocol-type 'sni' \
    --min-tls-version '1.2'
```


# Log Analytics

## Request URIs aggregated by client

```
AzureDiagnostics
| where Category == "AzureCdnAccessLog" and endpoint_s == "www-arnavion-dev.azureedge.net"
| extend client = strcat("[", clientIp_s, "] ", userAgent_s)
| summarize count_client_requestUri = count() by client, requestUri_s
| order by client asc, count_client_requestUri desc
| summarize
    count_client = sum(count_client_requestUri),
    make_list(pack(requestUri_s, count_client_requestUri))
    by client
| order by count_client desc, client asc
| project count_client, client, list_
```

## Request clients aggregated by URI

```
AzureDiagnostics
| where Category == "AzureCdnAccessLog" and endpoint_s == "www-arnavion-dev.azureedge.net"
| extend client = strcat("[", clientIp_s, "] ", userAgent_s)
| summarize count_client_requestUri = count() by client, requestUri_s
| order by requestUri_s asc, count_client_requestUri desc
| summarize
    count_requestUri = sum(count_client_requestUri),
    make_list(pack(client, count_client_requestUri))
    by requestUri_s
| order by count_requestUri desc, requestUri_s asc
| project count_requestUri, requestUri_s, list_
```
