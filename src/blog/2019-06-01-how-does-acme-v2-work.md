---
title: '2019-06-01 How does ACME v2 work?'
date: '2019-06-01T00:00:00Z'
---

Over the last few weeks, I've been setting up this website on Azure. It's a simple static website, so the setup is just to upload the static assets to an Azure Storage Account and set up an Azure CDN with a custom domain name in front of it. I also wanted to use my own custom TLS certificate for it sourced from [Let's Encrypt,](https://letsencrypt.org){ rel=nofollow } which means I needed to set up an automatic renewal workflow for said cert. But the web server is in Azure CDN's control so I can't run something turnkey like [Certbot.](https://certbot.eff.org/){ rel=nofollow } Besides, I wanted to do this as much as possible by myself rather than relying on third-party stuff anyway, so I implemented my own ACME renewal workflow that runs periodically in an Azure Function.

I'll write more details about the Azure setup later. For now, I want to share what I learned about the ACME v2 protocol by providing a simple explanation of how the simplest-possible client implementation works.


<section>
<h2 id="introduction">[Introduction](#introduction)</h2>

The ACME v2 protocol is still in draft RFC status as of this writing. It also uses concepts from other RFCS.

- [RFC 4648 - The Base16, Base32, and Base64 Data Encodings](https://tools.ietf.org/html/rfc4648){ rel=nofollow }
- [RFC 7517 - JSON Web Signature](https://tools.ietf.org/html/rfc7515){ rel=nofollow }
- [RFC 7517 - JSON Web Key](https://tools.ietf.org/html/rfc7517){ rel=nofollow }
- [RFC 7518 - JSON Web Algorithms (JWA)](https://tools.ietf.org/html/rfc7518){ rel=nofollow }
- [RFC 7638 - JSON Web Key (JWK) Thumbprint](https://tools.ietf.org/html/rfc7638){ rel=nofollow }
- [RFC Draft - Automatic Certificate Management Environment (ACME)](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html){ rel=nofollow }

You don't have to read them in their entirety before you start, but it helps to have them open for reference. I will link to the relevant sections of the RFCs where necessary.

An ACME server is the entity that provides the TLS certificate. An ACME client is the entity that creates a certificate signing request (CSR) and submits it to the ACME server for signing. The ACME server then performs some validation to verify that the client owns the domain(s) that it is requesting a certificate for, which involves multiple back-and-forths between the client and the server. Finally, the server returns a certificate to the client which the client can then start using.

The A in ACME stands for Automatic, and indeed the great thing about the protocol is that it can be completely automated. All interaction between the client and server is via the HTTP protocol.

</section>


<section>
<h2 id="create-an-account-key">[Create an account key](#create-an-account-key)</h2>

All interactions with the server other than the directory request and the "new nonce" request are authenticated. The client generates an account key in one of the formats supported by the server based on [section 3.1 "alg" (Algorithm) Header Parameter Values for JWS in the JSON Web Algorithm RFC](https://tools.ietf.org/html/rfc7518#section-3.1){ rel=nofollow } with restrictions as noted in [section 6.2 Request Authentication of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.6.2){ rel=nofollow } The client uses this key to sign its requests using the JSON Web Signature RFC.

Check your ACME server provider's documentation for the keys it supports. In the case of Let's Encrypt, the strongest format it supports (as of this writing) are ECDSA P-384 keys. The rest of this document will use these keys for the examples.

</section>


<section>
<h2 id="discover-the-server-urls">[Discover the server URLs](#discover-the-server-urls)</h2>

An ACME client starts off by querying the ACME server's directory URL with an HTTP GET request. For Let's Encrypt, the production service's directory URL is `https://acme-v02.api.letsencrypt.org/directory`. It also has a staging service at directory URL `https://acme-staging-v02.api.letsencrypt.org/directory`. You should use the staging service while developing your client, since it is more lenient regarding throttling and issuing duplicate certificates.

The server responds to the directory request with a `200 OK` response. This response is a JSON object that maps URL types to URLs, like this:

```
{
    "newAccount": "...",
    "newNonce": "...",
    "newOrder": "..."
}
```

- The `newAccount` value is the "new account" URL.
- The `newNonce` value is the "new nonce" URL.
- The `newOrder` value is the "new order" URL.

The directory response is described in [section 7.1.1 Directory of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.1){ rel=nofollow }

</section>


<section>
<h2 id="get-the-initial-nonce">[Get the initial nonce](#get-the-initial-nonce)</h2>

To prevent replay attacks, all requests that contain a request body must contain a nonce as part of the request body. The value of this nonce comes from the `Replay-Nonce` header in the previous response from the server. Thus the client must check every response it receives to see if it contain this header, and maintain a state that holds this nonce so that it can use it for the next request.

It is possible for the server to return a `Replay-Nonce` header in the response of the directory request itself. In case the server does not do so, the client gets an initial nonce by sending an HTTP HEAD request to the "new nonce" URL. The client expects the server to respond with a `200 OK` response that definitely contains a `Replay-Nonce` header.

</section>


<section>
<h2 id="the-post-request-format">[The POST request format](#the-post-request-format)</h2>

All interactions with the server other than the directory request and the "new nonce" request are HTTP POST requests, and contain a request body that is a JWS envelope around the actual payload. This is a multi-step process based on the JSON Web Signature RFC linked above.


<section>
<h3 id="the-encoded-payload">[The "encoded payload"](#the-encoded-payload)</h3>

The client starts with the payload that it wants to send. This might be an empty payload, or it might be an object. In the latter case, the client serializes the object to a JSON string, then encodes the string using the encoding described in [section 5 Base 64 Encoding with URL and Filename Safe Alphabet of RFC 4648.](https://tools.ietf.org/html/rfc4648#section-5){ rel=nofollow } This is now the "encoded payload".

It is important to note that the payload can be empty, which means the "encoded payload" is the empty string. The HTTP POST request still has a request body, since this empty "encoded payload" is still wrapped in a JWS envelope as described below. Specifically, the payload is empty in what the ACME RFC calls "POST-as-GET" requests, which refers to requests that get the current status of an object like a REST GET request would, but are nevertheless sent as POST requests with a JWS body. See [section 6.3 GET and POST-as-GET Requests of the ACME RFC](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.6.3){ rel=nofollow } for more details.

Note that the URL-safe base64 encoding is the only kind of encoding used in the entire client workflow. Future references to base64 encoding in this document will refer to this same URL-safe encoding.

</section>


<section>
<h3 id="the-protected-header">[The "protected header"](#the-protected-header)</h3>

Next, the client constructs the "protected header" for the request. The client first creates the protected header object, which looks like this:

```
{
    "alg": "ES384",
    "nonce": "...",
    "url": "...",
    "jwk": {
        "crv": "P-384",
        "kty": "EC",
        "x": "...",
        "y": "..."
    }
}
```

or like this:

```
{
    "alg": "ES384",
    "nonce": "...",
    "url": "...",
    "kid": "..."
}
```

The difference between the two formats is in the choice of the fourth parameter, either `jwk` or `kid`. The choice of parameter depends on whether the client knows the account URL or not.

- The `alg` value is the identifier of the algorithm the client used to create the account key. `ES384` represents an ECDSA P-384 key. See [section 3.1 "alg" (Algorithm) Header Parameter Values for JWS in the JSON Web Algorithm RFC](https://tools.ietf.org/html/rfc7518#section-3.1){ rel=nofollow } for the list of values corresponding to other key types.

- The `nonce` value is the nonce string from the previous response, as explained previously.

- The `url` value is the URL of the current request, ie the "new account" URL.

- If the client does not know the account URL, it must set the `jwk` parameter to a value that describes the account key. The example is for the ECDSA P-384 key format. For other formats, the `kty` parameter identifies the format using the identifiers listed in [section 6.1 of the JSON Web Algorithm RFC.](https://tools.ietf.org/html/rfc7518#section-6.1){ rel=nofollow } The other parameters vary depending on the key type, and are documented in the other subsections of section 6 in the same RFC.

- If the client does know the account URL, it must set the `kid` parameter to the account URL.

The client then serializes this protected header object to JSON and base64-encodes it. The result is the "protected header".

</section>


<section>
<h3 id="the-signature">[The "signature"](#the-signature)</h3>

Lastly, the client needs to construct the "signature" of the request. It takes the "protected header", appends an ASCII `. (U+002E)`, then appends the "encoded payload". This resulting string is then converted to bytes in the ASCII encoding, and these ASCII-encoded bytes are the signature input. The client then uses the key to sign this signature input and get the signature bytes. The signature bytes are base64-encoded into a string, which becomes the "signature" of the request.

The signing algorithm depends on the key type. For ECDSA P-384 keys the algorithm is SHA-384. For other formats, see [section 3.1 "alg" (Algorithm) Header Parameter Values for JWS in the JSON Web Algorithm RFC.](https://tools.ietf.org/html/rfc7518#section-3.1){ rel=nofollow }

</section>


The client now constructs the HTTP request body. It is a JSON object that looks like this:

```
{
    "payload": "...",
    "protected": "...",
    "signature": "..."
}
```

- The `payload` value is the "encoded payload".

- The `protected` value is the "protected header".

- The `signature` value is the "signature".

The client also sets the `Content-Type: application/jose+json` header on the request.

</section>


<section>
<h2 id="create-an-account">[Create an account](#create-an-account)</h2>

The client constructs a new account payload that looks like this:

```
{
    "contact": [
        "..."
    ],
    "termsOfServiceAgreed": true
}
```

The `contact` value is an array of strings, each one representing a contact URL for the account owner. The simplest choice is to have a single `mailto` URL for the webmaster of the domain that you're planning to get the certificate for, such as `"mailto:webmaster@example.com"`.

The `termsOfServiceAgreed` value is a boolean representing whether the client agrees to the terms of service of the server. The URL to the terms of service is returned in the initial directory response, and the protocol expects that the client will involve some human interaction to fetch and agree to them.

The client sends an HTTP POST request to the "new account" URL with this payload in a JWS envelope. Since it does not have the account URL at this point, it uses the first format of the protected header that contains the `jwk` key.

The client expects the server to return a `201 Created` or `200 OK` response. The former implies that the server has created a new account corresponding to the account key, while the latter indicates the server has already seen this account key before and so will use the existing account.

The body of the response contains a JSON object representing the account, like this:

```
{
    "status": "..."
}
```

- The `status` value is the state of the account, and must be the value `"valid"` to be able to proceed.

The response is described in full detail in [section 7.1.2 Account Objects of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.2){ rel=nofollow }

The response also contains a `Location` header that contains the "account URL". This account URL uniquely identifies the account, and is used in all future requests as the `kid` value of the "protected header". Thus the client must save it in its state.

As mentioned above, the server returns a `200 OK` response if it already has an existing account corresponding to the account key. In this way, the "new account" URL also functions as a "get existing account" URL. Thus if the client wants to reuse the same account key multiple times, it can use the "new account" URL to "discover" the account URL of the existing account corresponding to that account key. The server allows the client to omit the `"termsOfServiceAgreed"` key if the account already exists, unless the terms of service have changed since the last time the client set `"termsOfServiceAgreed"` to `true` for this account.

Alternatively, if the client expects the account to have already been created previously, it can persist the account key *and* the account URL, and skip posting to the "new account" URL entirely. However it should probably still POST-as-GET the account URL itself, just to make sure the account is still in the `"valid"` state.

</section>


<section>
<h2 id="create-an-order">[Create an order](#create-an-order)</h2>

The next step is to place an "order" for the certificate that the client wants. To do this, the client constructs the new order request payload, which looks like this:

```
{
    "identifiers": [
        { "type": "dns", "value": "..." }
    ]
}
```

Each value of the `identifiers` array represents an identifier that must be validated. The `value` of each identifier is the domain name that the client wants to request a certificate for.

The client sends an HTTP POST request to the "new order" URL with this payload in a JWS envelope. As mentioned above, since the client now knows the account URL, it uses the second format of the protected header that contains the `kid` key.

The client expects the server to return a `201 Created` response. If the order for these identifiers already existed and that order is still valid, then the server returns the existing order. The response status code is still `201 Created` in this case.

The response contains a `Location` header that contains the "order URL". The client should save this URL in its order state.

The body of this response contains a JSON object representing the order, like this:

```
{
    "status": "..."
}
```

- The `status` value represents the state of the order, and is used to determine how to proceed.

The response is described in full detail in [section 7.1.3 Order Objects of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.3){ rel=nofollow }

- If the order is in the `"pending"` state, the server is waiting for the client to complete the authorizations of the order. The client handles the order as described in the [The order is `"pending"`](#the-order-is-pending) section below.

- If the order is in the `"ready"` state, the authorizations of the order have already been completed and the order is waiting to be finalized. The client handles the order as described in the [The order is `"ready"`](#the-order-is-ready) section below.

- If the order is in the `"processing"` state, the order has already been finalized, and is being processed by the server. The client should continue to poll the order using the order URL until it has moved to another state.

- If the order is in the `"valid"` state, the order has already been completed. The client handles the order as described in the [The order is `"valid"`](#the-order-is-valid) section below.

- If the order is in the `"invalid"` state, the server has rejected the order. The client should abort the order workflow.

Creating an order is described in [section 7.4 Applying for Certificate Issuance of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.4){ rel=nofollow } The change of state of an order object is described in [section 7.1.6 Status Changes of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.6.p.4){ rel=nofollow }

</section>


<section>
<h2 id="the-order-is-pending">[The order is `"pending"`](#the-order-is-pending)</h2>

If the order is in the `"pending"` state, the server is waiting for the client to complete the authorizations of the order. The order object looks like this:

```
{
    "authorizations": [
        "...",
        ...
    ],
    "status": "pending"
}
```

- The `authorizations` value is an array of strings, each of which represents an "authorization URL" for this order. There will be one such URL for each identifier in the order request.

The server is waiting for the client to complete the authorizations of the order. As mentioned previously, there will be one authorization URL for each identifier the client sent in the initial order request. Each authorization contains a set of challenges that prove that the client has ownership of the corresponding domain.

The client completes every authorization before proceeding with the order.


<section>
<h3 id="completing-an-authorization">[Completing an authorization](#completing-an-authorization)</h3>

The client fetches the authorization object by performing a POST-as-GET request to the authorization URL, and expects the server to return a `200 OK` response. The response contains a JSON object that represents the current state of the authorization, like this:

```
{
    "challenges": [
        { "type": "...", "token": "...", "url": "...", "status": "..." },
        ...
    ],
    "status": "..."
}
```

- The `challenges` value of the authorization object is an array of challenge objects.

	- The `type` value of a challenge object is the type of the challenge. For example, an http-01 challenge has the value `"http-01"`.

	- The `token` value is the token of the challenge. This has different uses depending on the type of the challenge.

	- The `url` value is the URL of the challenge. The client uses this URL to indicate to the server that it has satisfied the requirements of the challenge, so the server should begin its verification. The client also polls this URL to get the updated state of the challenge.

		The response returned from posting to the challenge URL is a JSON object that is identical to this challenge object in the `challenges` array.

	- The `status` value is the state of the challenge.

- The value of the `status` key of the object in the response body represents the state of the order, and is used to determine how to proceed.

The authorization object is described in full detail in [section 7.1.4 Authorization Objects of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.4){ rel=nofollow }

- If the authorization is in the `"pending"` state, it is waiting for the client to fulfill at least one challenge of the order.

- If the authorization is in the `"valid"` state, it has already been completed and succeeded, and there is nothing more to do for this authorization.

- If the authorization is in the `"invalid"` state, it has already been completed and failed. The parent order of this authorization would've been marked as `"invalid"` as well, so the client should abort the order workflow.

To complete a pending authorization, the client chooses one of its challenges and tries to fulfill it.

- If the challenge is in the `"pending"` state, it is waiting for the client to satisfy the requirements of the challenge depending on its type. Once the client has done so, it sends an HTTP POST request to the challenge URL with an empty JSON object as the payload (note: not an empty payload, but an empty object `{}` as the payload) and expects a `200 OK` response. It then polls the challenge URL to get its updated status with an empty payload (note: not an empty object, but an empty payload, just like a regular POST-as-GET request).

	See [Extra: Fulfilling an http-01 challenge](#extra-fulfilling-an-http-01-challenge) for how to fulfill an http-01 challenge.

	See [Extra: Fulfilling a dns-01 challenge](#extra-fulfilling-a-dns-01-challenge) for how to fulfill a dns-01 challenge.

- If the challenge is in the `"processing"` state, the client has previously posted to the challenge URL. The server is still verifying the challenge, so the client should continue to poll the challenge URL.

- If the challenge is in the `"valid"` state, the client has previously posted to the challenge URL and the server has verified the challenge successfully. There is nothing more for the client to do with this challenge.

- If the challenge is in the `"invalid"` state, the client has previously posted to the challenge URL and the server has rejected the challenge. The parent authorization of this challenge, and thus the parent order of that authorization, would've been marked as `"invalid"` as well, so the client should abort the order workflow.

Note that it is possible for the challenge to remain in the `"pending"` state for a short period of time after the client has posted to the challenge URL, rather than immediately moving to `"processing"` state. If the client knows that it has already posted to the challenge URL, it should treat this just like if the challenge was in the `"processing"` state and continue polling the challenge URL, waiting for it to change state. (This behavior appears to violate the RFC, but is displayed by Let's Encrypt.)

The change of state of an authorization object is described in [section 7.1.6 Status Changes of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.6.p.3){ rel=nofollow } The change of state of a challenge object is described in [section 7.1.6 Status Changes of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.7.1.6.p.2){ rel=nofollow }

Once the client observes that the challenge is in the `"valid"` state, it polls the authorization at the authorization URL till the authorization too reaches the `"valid"` state, as described above.

</section>


Once every authorization in the order is `"valid"`, the client polls the order, waiting for it to reach the `"ready"` state, as described above.

</section>


<section>
<h2 id="the-order-is-ready">[The order is `"ready"`](#the-order-is-ready)</h2>

If the order is in the `"ready"` state, the authorizations of the order have already been completed and the order is waiting to be finalized. The order object looks like this:

```
{
    "finalize": "...",
    "status": "ready"
}
```

- The `finalize` value is a string representing the "finalize URL" of this order.

The client constructs a DER-encoded certificate signing request (CSR). Depending on the ACME server provider, there may be various restrictions on the key type, key size, and properties of the CSR. For example, Let's Encrypt enforces that the account key is not reused as the CSR private key, and that the CSR does not contain `Not Before` and `Not After` properties since Let's Encrypt sets these itself.

The client stores the private key of the CSR in its state. It then sends an HTTP POST request to the order's "finalize URL" with a payload that looks like this:

```
{
    "csr": "..."
}
```

- The `csr` value is the base64-encoded CSR.

The client expects an `200 OK` response from the server, with a response containing the updated order object. It then polls the order URL until the order has reached the `"valid"` state.

</section>


<section>
<h2 id="the-order-is-valid">[The order is `"valid"`](#the-order-is-valid)</h2>

If the order is in the `"valid"` state, the order has been completed. The order object looks like this:

```
{
    "certificate": "...",
    "status": "valid"
}
```

- The `certificate` value is a string representing the URL of the signed certificate.

The client downloads the certificate from this URL using a POST-as-GET request. It combines this certificate with the private key of the CSR it had generated previously, and begins using it for its webserver. This is the end of the order workflow.

</section>


<section>
<h2 id="summary">[Summary](#summary)</h2>

I hope this serves as a useful starting point for anyone wanting to implement an ACME v2 client from scratch. Of course, there are far more details in the ACME RFC that I haven't covered here, such as revoking certificates, account management and error response formats. Check the RFC if something doesn't work the way I describe it here.

</section>


<section>
<h2 id="extra-fulfilling-an-http-01-challenge">[Extra: Fulfilling an http-01 challenge](#extra-fulfilling-an-http-01-challenge)</h2>

To fulfill an http-01 challenge, the client instructs the webserver of the domain to respond to a certain URL with certain content. The URL and content are derived from the challenge properties and are thus unique to that particular challenge. To verify the challenge, the ACME server fetches this URL (using the `http` scheme) and verifies that it has the content it expected. Being able to instruct the webserver in this way counts as proof that the client owns the domain.

First, the client computes its "JWK thumbprint". It does this by taking the same JWK object that it used as the `jwk` value in the "new account" request, then serializing it to canonical JSON. Then it gets the UTF-8 bytes of the JSON string, hashes the bytes with SHA-256, and base64-encodes the hash bytes. The resulting string is the "JWK thumbprint".

Note that it is important to serialize the JWK object using canonical JSON (no whitespace, keys in lexical order) to ensure that both the client and server serialize the key to the same result.

Also note that it is required to use SHA-256 for the hash operation, not the key-format-dependent hash operation used to sign JWS payloads. See [RFC 7638](https://tools.ietf.org/html/rfc7638){ rel=nofollow } for more details.

The client then takes the challenge token, appends an ASCII `. (U+002E)`, then appends the "JWK thumbprint". This resulting string encoded to UTF-8 bytes becomes the content of the challenge response. The URL of the challenge response is `/.well-known/acme-challenge/$(challenge.token)`

http-01 challenges are described in [section 8.3 HTTP Challenge of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.8.3){ rel=nofollow }

</section>


<section>
<h2 id="extra-fulfilling-a-dns-01-challenge">[Extra: Fulfilling a dns-01 challenge](#extra-fulfilling-a-dns-01-challenge)</h2>

To fulfill a dns-01 challenge, the client instructs the DNS server that responds for the domain to serve a specific TXT record with certain content. The name of the TXT record is `_acme-challenge.$domain`. Its text content is derived from the challenge properties and is thus unique to that particular challenge. To verify the challenge, the ACME server queries the TXT record and verifies that it has the content it expected. Being able to instruct the DNS server in this way counts as proof that the client owns the domain.

Similar to the http-01 challenge process described above, the client constructs a string by taking the challenge token and appending an ASCII `. (U+002E)` and the "JWK thumbprint" to it. This resulting string becomes the contents of the TXT record.

dns-01 challenges are described in [section 8.4 DNS Challenge of the ACME RFC.](https://ietf-wg-acme.github.io/acme/draft-ietf-acme-acme.html#rfc.section.8.4){ rel=nofollow }

Unlike an http-01 challenge, a dns-01 challenge can be used for arbitrary non-HTTP endpoints that need to serve TLS. dns-01 challenges are also the only kind of challenge that Let's Encrypt accepts when requesting certs for a wildcard domain. (For a wildcard domain order like `*.example.org`, the TXT record that the server will resolve is `_acme-challenge.example.org`

You will of course need a programmable DNS server so that the ACME client can dynamically modify the `_acme-challenge.$domain` DNS record. If your domain's DNS server does not allow such programmatic access, you can set up a separate programmable DNS server just for the `_acme-challenge.$domain` record, and manually configure an NS record for `_acme-challenge.$domain` in your domain's DNS server to point to your programmable one.

</section>
