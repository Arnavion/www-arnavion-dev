---
title: "2019-08-04 Let's Encrypt via Azure Function"
date: '2019-08-04T00:00:00Z'
---

<a href="{{< relref "./2019-06-01-how-does-acme-v2-work.md" >}}">Last time,</a> I mentioned how this website is set up on Azure.

>It's a simple static website, so the setup is just to upload the static assets to an Azure Storage Account and set up an Azure CDN with a custom domain name in front of it. I also wanted to use my own custom TLS certificate for it sourced from [Let's Encrypt,](https://letsencrypt.org) which means I needed to set up an automatic renewal workflow for said cert. But the web server is in Azure CDN's control so I can't run something turnkey like [Certbot.](https://certbot.eff.org/) Besides, I wanted to do this as much as possible by myself rather than relying on third-party stuff anyway, so I implemented my own ACME renewal workflow that runs periodically in an Azure Function.
>
>I'll write more details about the Azure setup later.

The Azure setup for renewing the Let's Encrypt cert ran successfully for the first time yesterday, so this is the right time to talk about it.


{{% section %}}
{{% h 2 "What do you need to set up a static web site hosted on Azure?" %}}

- An Azure Storage account.

    This storage account is used to host the files served by the static website. You have to enable it to serve static websites, after which it automatically gets a contained named `$web`. Any files you put inside this container are served by the storage account's blob HTTP endpoint.

- An Azure CDN profile and endpoint.

    Since I want to use my own custom domain instead of the storage account's blob HTTP endpoint, I also provisioned an Azure CDN profile in front of the storage account. This also means every HTTP request does not go to the single storage account in the US, but to the CDN cache that has endpoints all over the world.

    Note that the CDN endpoint's origin type must be set to "Custom origin" and point to the storage account's web endpoint. You don't want to set it to "Storage", because then the container name becomes part of the URL, like `https://cdnendpoint.azureedge.net/$web/index.html`

- A custom domain. Configure your domain's DNS to add a CNAME record pointing to the CDN endpoint, and configure the CDN endpoint itself to accept the custom domain.

- An Azure KeyVault to host the Let's Encrypt account key, and the HTTPS certificate itself.

- An Azure Function app to periodically run the cert renewal workflow.

- An Azure Service Principal for the identity of the Function app, with access to the storage account, KeyVault and CDN endpoint. Alternatively, use the "Managed Service Identity" of the Function app.

{{% /section %}}


{{% section %}}
{{% h 2 "Design of the Let's Encrypt auto-renewal Function app" %}}

While Azure CDN does support provisioning and using a certificate automatically (via DigiCert), I found this process very unreliable. It's supposed to be that you just select the "CDN managed" option and Azure reaches out to Digicert and provisions the cert. However I waited many hours and this never happened. If you search around, you'll find other people with this problem got it resolved by having Azure customer support manually resend the request to DigiCert.

Eventually I did see the cert provisioned by DigiCert on [crt.sh,](https://crt.sh/?q=www.arnavion.dev) but by then I'd given up on it and aborted the process from the Azure end.

So this was a good opportunity to use Let's Encrypt instead.

Function apps are limited in [what programming languages they support.](https://docs.microsoft.com/en-us/azure/azure-functions/supported-languages) I wanted to only use one of the GA languages and not the preview ones, so I had a choice between Java, JavaScript and any .Net Core language. I decided to go with F#, as that is the most modern and type-safe language among the choices I had.

You can find the code [here.](https://github.com/Arnavion/acme-azure-function) It includes an ARM deployment template plus manual steps to deploy everything listed above.

There are two distinct processes of getting a cert on your CDN endpoint - provisioning the cert from Let's Encrypt, and deploying the provisioned cert to the CDN endpoint. Technically the process that deploys the cert to the CDN doesn't care where the cert came from, so it should be independent of the process that provisions the cert. That's why there are two functions in the Function app:

- `RenewKeyVaultCertificateOrchestratorManager`

    This function checks whether the cert needs to be renewed. If it does, it performs the ACME workflow, including uploading the http-01 challenge blob to the storage account, and uploads the final cert to the KeyVault.

- `UpdateCdnCertificate`

    This function compares the cert that the CDN is currently configured to use with the one in the KeyVault. If they differ, it deploys the KeyVault cert to the CDN.

Also, as a general principle, I did not want to use any of the existing Azure libraries for interacting with its REST API. I've had bad experiences with them in the past given that they pull in megabytes of dependencies and frequently have conflicts with the versions of those dependencies. I would also have to keep on top of their new releases / CVEs and update the dependency versions. Instead, I just wrote the minimal amount of code I needed to directly make HTTP requests to the REST API endpoints for the operations I cared about.

I did however have to depend on the `Microsoft.NET.Sdk.Functions` package, since it contains the types and attributes you need to write the functions so that they can be loaded from the host.

{{% /section %}}


{{% section %}}
{{% h 2 "Accessing Azure resources" %}}

The Function app needs OAuth2 tokens from Azure Active Directory, one for each Azure resource that it wants to access. There are two ways of getting these tokens:

1. Use an Azure Service Principal (SP).

    Create an SP and save its `appId` and `password` in your function app's settings, along with your subscription's "tenant ID". The `appId` is the "client ID", and the `password` is the "client secret". The app uses them by sending an HTTP POST request to `https://login.microsoftonline.com/${TENANT_ID}/oauth2/token` with a URL-encoded form body that looks like:

    ```
    grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&resource=${RESOURCE}
    ```

1. Use the app's "Managed Service Identity" (MSI).

    There will be two environment variables set on its process named `MSI_ENDPOINT` and `MSI_SECRET`. The app sends an HTTP GET request to `${MSI_ENDPOINT}?resource=${RESOURCE}&api-verson=2017-09-01` with a `Secret` header set to `${MSI_SECRET}`.

    Well, I assume that's how it works, based on [the code in the `Microsoft.Azure.Services.AppAuthentication` library.](https://github.com/Azure/azure-sdk-for-net/blob/db74f3ec0b3c3c7da971acc76df04da749658321/sdk/mgmtcommon/AppAuthentication/Azure.Services.AppAuthentication/TokenProviders/MsiAccessTokenProvider.cs) I use the Linux runtime for my Function app, and currently [MSI does not work for Linux Function apps,](https://github.com/Azure/Azure-Functions/issues/1066) so I did not implement and test it.

In either case, the app should get a `200 OK` response, with a JSON body that looks like this:

```json
{
    "access_token": "...",
    "token_type": "..."
}
```

The app then constructs an HTTP `Authorization` header that looks like `Authorization: ${TOKEN_TYPE} ${ACCESS_TOKEN}`, and uses this header for all requests to that resource.

The value of the `RESOURCE` component depends on what Azure resource the app wants to operate on:

- For working with the Azure Management API, `RESOURCE` is `https://management.azure.com`

- For working with the contents of an Azure KeyVault, `RESOURCE` is `https://vault.azure.net`. This does not apply to operations on the KeyVault itself, which are part of the management API and use the Management API `Authorization` header.

- For working with blobs in an Azure Storage Account, `RESOURCE` is `https://storage.azure.com`. This does not apply to operations on the storage account itself, which are part of the management API and use the Management API `Authorization` header.

See [here](https://docs.microsoft.com/en-us/rest/api/azure/) for the official documentation of how to construct these `Authorization` headers.

{{% /section %}}


{{% section %}}
{{% h 2 "Azure REST API" %}}

Here are links to the REST API docs for the specific operations that the Function app uses.

- CDN

    Use the Management API `Authorization` header for all requests.

    - [Get the certificate name and version that a custom domain is currently set to use](https://docs.microsoft.com/en-us/rest/api/cdn/customdomains/get)

        The documentation of the response body is outdated and does not mention the `properties.customHttpsParameters` value. Specifically, the response will be a JSON object that looks like:

        ```json
        {
            "properties": {
                "customHttpsParameters": { ... }
            }
        }
        ```

        This `properties.customHttpsParameters` value is the same as the `UserManagedHttpsParameters` object described [here.](https://docs.microsoft.com/en-us/rest/api/cdn/customdomains/enablecustomhttps#usermanagedhttpsparameters)

        Note that, despite their names, the `properties.customHttpsParameters.certificateSourceParameters.secretName` and `.secretVersion` values are not specific to KeyVault secrets and also apply to KeyVault certificates. (The private key of a KeyVault certificate is implicitly a KeyVault secret.)


    - [Set the certificate name and version that a custom domain should use](https://docs.microsoft.com/en-us/rest/api/cdn/customdomains/enablecustomhttps)

        Use the `UserManagedHttpsParameters` form of the request body, not the `CdnManagedHttpsParameters` form, and set `protocolType` to `ServerNameIndication`.

        The documentation is wrong about the API version. The API version must be `2018-04-02` or higher, not `2017-10-12` as the documentation suggests. If you use `2017-10-12` then the CDN API will ignore the `certificateSource` and `certificateSourceParameters` and start provisioning a "CDN managed" cert from DigiCert. (This mistake is also present in [the example in the ARM specs repository.](https://github.com/Azure/azure-rest-api-specs/blob/37fcc6d2c5e25243dd737ac5b940895de5ee47a2/specification/cdn/resource-manager/Microsoft.Cdn/stable/2017-10-12/examples/CustomDomains_EnableCustomHttpsUsingBYOC.json))

        This operation is asynchronous (returns `202 Accepted`) and can take many hours to complete, so it's possible for the function to time out waiting for it to complete. It may be sufficient to poll it for a few minutes to ensure it doesn't fail, and then assume it will eventually succeed.


- KeyVault

    Use the KeyVault API `Authorization` header for all requests.

    - [Get a certificate's version and expiry](https://docs.microsoft.com/en-us/rest/api/keyvault/getcertificate/getcertificate)

        If there are multiple versions of this cert, the response only contains the latest one.

    - [Upload a certificate](https://docs.microsoft.com/en-us/rest/api/keyvault/importcertificate/importcertificate)

        Only the `value` field is required. KeyVault will automatically set the attributes like `exp` and `nbf` by parsing the certificate.

        If the cert of this name already exists, the original cert will be marked an older version of the cert.

    - [Get a secret](https://docs.microsoft.com/en-us/rest/api/keyvault/getsecret/getsecret)

    - [Set a secret](https://docs.microsoft.com/en-us/rest/api/keyvault/setsecret/setsecret)

        It's useful to set the `contentType` to a MIME type like `appliction/octet-stream` so that the portal does not try to render it as text. Otherwise only the `value` field is required.


- Storage Account

    - [Enable / disable HTTP access to the storage account](https://docs.microsoft.com/en-us/rest/api/storagerp/storageaccounts/update)

        Set the `properties.supportsHttpsTrafficOnly` field.

        Use the Management API `Authorization` header for these requests.

    - [Create a blob in the storage account](https://docs.microsoft.com/en-us/rest/api/storageservices/put-blob)

        Use the Storage Account API `Authorization` header for these requests. Apart from that, set the `Content-Type` (`application/octet-stream`), `Date`, `x-ms-blob-type` (`BlockBlob`) and `x-ms-version` (`2018-03-28`) headers. Other headers are not required.

    - [Delete a blob from the storage account](https://docs.microsoft.com/en-us/rest/api/storageservices/delete-blob)

        Use the Storage Account API `Authorization` header for these requests. Apart from that, set the `Date` and `x-ms-version` (`2018-03-28`) headers. Other headers are not required.

{{% /section %}}


{{% section %}}
{{% h 2 "Miscellaneous caveats" %}}


{{% section %}}
{{% h 3 "Using the Azure SDKs / clients" %}}

Support for "user managed" certs for Azure CDN is not complete in all Azure SDKs and clients.

- The .Net SDK only started supporting the feature in [2019-03](https://github.com/Azure/azure-sdk-for-net/commit/2fd9988c74ccc13897246fedf1fc9a9deaa4209c)

- The `Enable-AzureCdnCustomDomainHttps` PowerShell command [still does not support it.](https://github.com/Azure/azure-powershell/blob/7f036cad8c3c2ac9fa8af30c3d8e918171cd82c9/src/Cdn/Cdn/CustomDomain/EnableAzureRmCdnCustomDomainHttps.cs#L31-L60)

- The `az` CLI tool does apparently support it via `az cdn custom-domain enable-https --custom-domain-https-parameters`, but does not explain how to set the `custom-domain-https-parameters` parameter. [This GitHub issue from 2019-07](https://github.com/Azure/azure-cli/issues/9894) assumed it would be a JSON object, but ran into trouble using it anyway.

If you do use an SDK or client, make sure it doesn't end up using the "CDN managed" certs, either because it doesn't let you specify KeyVault certificate source parameters, or because it internally uses an API version lower than `2018-04-02`

{{% /section %}}


{{% section %}}
{{% h 3 "Why use the Linux runtime for the Function app?" %}}

When the Function app receives the cert from Let's Encrypt, it combines the cert with the private key and uploads it to the KeyVault. Then it tells the CDN to use this cert.

When I was coding up the Function app, I was doing it on Windows. I had no problem with combining and uploading the cert to the KeyVault, but the CDN API to make CDN use the cert would fail. To be sure, I also did it manually from the Azure Portal, and it failed in the same way:

>The server (leaf) certificate doesn't include a private key or the size of the private key is smaller than the minimum requirement.

I was sure the cert I uploaded to KeyVault absolutely did have a private key, and that the key was 4096 bits, so this error did not make any sense. The error message also didn't say anything about what "the minimum requirement" might be. The closest thing to any requirements I could find was [this page](https://docs.microsoft.com/en-us/azure/cdn/cdn-troubleshoot-allowed-ca) that lists the CAs that Azure CDN allows, and it does contain DST Root CA X3 (Let's Encrypt's parent CA).

I filed a support request on 2019-05-13. Surprisingly, from 2019-05-14, the error message from the CDN API changed to:

>We were unable to read the private key for the certificate provided. The server (leaf) certificate private key may be corrupted.

The timing was probably a coincidence, but it did at least make it seem the key length was a red herring. However, I was still confident that the KeyVault certificate did contain a private key. To be even more confident, I spun up a local nginx server and it was able to use the cert without any problems.

There was one more red herring in the subsequent back-and-forth between me and the product developers (via customer support). Specifically, the product developers said:

>Verify the uploaded certificate is a KeyVault Secret, not a KeyVault Certificate

... as if implying that CDN does not support using KeyVault certificates, only secrets. But I did not believe this, since even [CDN's own documentation for user-managed certificates](https://docs.microsoft.com/en-us/azure/cdn/cdn-custom-ssl?tabs=option-2-enable-https-with-your-own-certificate) explicitly talks about using KeyVault certificates.

Eventually they realized the issue was that the private key in the cert was not marked "exportable", so even though it existed CDN was not able to access it. This is apparently a Windows-specific feature that works by adding [an `msPKI-Private-Key-Flag` attribute to the private key, that contains a `CT_FLAG_EXPORTABLE_KEY` flag.](https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-crtd/f6122d87-b999-4b92-bff8-f465e8949667) Windows and Windows tooling checks for the presence of this attribute and flag, and artificially rejects access to the private key if the flag is unset.

There are search results that mention using the `System.Security.Cryptography.X509Certificates.X509KeyStorageFlags.Exportable` flag. But since I was using `System.Security.Cryptography.X509Certificates.RSACertificateExtensions.CopyWithPrivateKey` to generate the combined cert, I could not see where I would set this attribute. Setting it on the original public cert's `X509Certificates2` object did not help, and there was no way to do it on the `System.Security.Cryptography.RSA` object for the private key either.

I thought about using a third-party library, but [`BouncyCastle`](https://www.nuget.org/packages/BouncyCastle/) was the only one I'd heard of and it doesn't support .Net Core. There is an unofficial fork [`Portable.BouncyCastle`](https://www.nuget.org/packages/Portable.BouncyCastle/) that claims to support .Net Core but [still internally uses API that is only implemented in .Net Framework,](https://stackoverflow.com/a/56213804/545475) so I could not assume that code which compiled would be guaranteed to work. In any case, I didn't want to use a third-party library for the same reason I didn't want to use the Azure .Net SDK - worrying about keeping the dependency up-to-date.

Since this is a Windows-specific attribute and only artificially prevents accessing the private key, I figured that non-Windows tooling would not have this problem. Indeed, openssl ignores the attribute and can export the key just fine, which is why my nginx server had no problem using the cert despite the "non-exportable" private key. Furthermore, .Net Core uses openssl to implement the `System.Security.Cryptography` API on Linux, and I confirmed that CDN was able to use the cert just fine when I generated it with `RSACertificateExtensions.CopyWithPrivateKey` on Linux.

So I decided to not waste any more time figuring out the right incantation of API to make it work on Windows, and settled on using the Linux runtime for the Function app.

{{% /section %}}


{{% section %}}
{{% h 3 "Do not use multiple Linux Function apps with the same storage account" %}}

A Function app uses a storage account for its bookkeeping. If you have multiple websites, you might have multiple Function apps, all with the same code but different settings. In this situation you may be tempted to have them all use the same storage account.

For Windows Function apps, each Function app's instance uses a unique name for itself derived from the Function app's name, so the instances of multiple Function apps can indeed co-exist in the same storage account just fine.

Unfortunately there is a bug with the way Azure deploys Linux Function apps that causes the Function app instances to derive their name differently. Instead of using the Function app name, they use the host machine name plus a hash of the path to their code entrypoint (the .Net DLL containing the function code). Furthermore, all host machines have the same machine name `(none)`, which gets sanitized into `none`. This means that if two Function apps have the same code, their instances will end up with the same name and clobber each other's data in the shared storage account.

It can lead to strange behavior like timer triggers not firing because the trigger firing in one app's instance convinces the other app's instance that *its* trigger already completed successfully. See [this GitHub issue from 2019-05](https://github.com/Azure/azure-functions-host/issues/4499) for more details. Unfortunately the repo has hundreds of unacknowledged issues so I assume it has not been noticed.

Hopefully it will be fixed before Linux Function apps become GA. Until then, do not configure more than one Linux Function app with the same storage account.

{{% /section %}}


{{% /section %}}
