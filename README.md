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
AZURE_RESOURCE_GROUP_NAME='www-arnavion-dev'
AZURE_STORAGE_ACCOUNT_NAME='wwwarnaviondev'
AZURE_CDN_PROFILE_NAME='www-arnavion-dev'
AZURE_CDN_ENDPOINT_NAME='www-arnavion-dev'

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
    --source "$PWD/out" --destination '$web' --type block \
    --verbose

az cdn endpoint purge \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" --profile-name "$AZURE_CDN_PROFILE_NAME" --name "$AZURE_CDN_ENDPOINT_NAME" \
    --content-paths '/*'
```
