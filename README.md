Source of <https://www.arnavion.dev/>

# Build

```sh
pwsh ./build.ps1
```


# Deploy

```sh
AZURE_RESOURCE_GROUP_NAME='website'
AZURE_STORAGE_ACCOUNT_NAME='arnaviondotdev'
AZURE_CDN_PROFILE_NAME='arnaviondotdev'
AZURE_CDN_ENDPOINT_NAME='arnaviondotdev'

AZURE_STORAGE_ACCOUNT_CONNECTION_STRING="$(
    az storage account show-connection-string \
        --resource-group "$AZURE_RESOURCE_GROUP_NAME" --name "$AZURE_STORAGE_ACCOUNT_NAME" \
        --query connectionString --output tsv
)"

az storage blob delete-batch \
    --connection-string "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" \
    --source '$web' \
    --verbose

az storage blob upload-batch \
    --connection-string "$AZURE_STORAGE_ACCOUNT_CONNECTION_STRING" \
    --source "$PWD/web" --destination '$web' --type block \
    --verbose

az cdn endpoint purge \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" --profile-name "$AZURE_CDN_PROFILE_NAME" --name "$AZURE_CDN_ENDPOINT_NAME" \
    --content-paths '/*'
```
