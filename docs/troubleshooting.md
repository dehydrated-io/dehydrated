# Troubleshooting

Generally if the following information doesn't provide a solution to your problem please take a look at existing issues (search for keywords) before creating a new one.

## "No registration exists matching provided key"

You probably changed from staging-CA to production-CA (or the other way).

Currently dehydrated doesn't detect a missing registration on the selected CA,
the current workaround is to move `private_key.pem` (and, if you care, `private_key.json`) out of the way so the scripts generates and registers a new one.

This will hopefully be fixed in the future.

## "Error creating new cert :: Too many certificates already issued for: [...]"

This is not an issue with dehydrated but an API limit with boulder (the ACME server).

At the time of writing this you can only create 5 certificates per domain in a sliding window of 7 days.

## "Certificate request has 123 names, maximum is 100."

This also is an API limit from boulder, you are requesting to sign a certificate with way too many domains.

## Invalid challenges

There are a few factors that could result in invalid challenges.

If you are using HTTP validation make sure that the path you have configured with WELLKNOWN is readable under your domain.

To test this create a file (e.g. `test.txt`) in that directory and try opening it with your browser: `http://example.org/.well-known/acme-challenge/test.txt`. Note that if you have an IPv6 address, the challenge connection will be on IPv6. Be sure that you test HTTP connections on both IPv4 and IPv6. Checking the test file in your browser is often not sufficient because the browser just fails over to IPv4.

If you get any error you'll have to fix your web server configuration.

## DNS invalid challenge since dehydrated 0.6.0 / Why are DNS challenges deployed first and verified later?

Since Let's Encrypt (and in general the ACMEv2 protocol) now supports wildcard domains there is a situation where DNS caching can become a problem.
If somebody wants to validate a certificate with `example.org` and `*.example.org` there are two tokens that have to be deployed on `_acme-challenge.example.org`.

If dehydrated would deploy and verify each token on its own the CA would cache the first token on `_acme-challenge.example.org` and the next challenge would simply fail.
Let's Encrypt uses your DNS TTL with a max limit of 5 minutes, but this doesn't seem to be part of the ACME protocol, just some LE specific configuration,
so with other CAs and certain DNS providers who don't allow low TTLs this could potentially take hours.

Since dehydrated now deploys all challenges first that no longer is a problem. The CA will query and cache both challenges, and both authorizations can be validated.
Some hook-scripts were written in a way that erases the old TXT record rather than adding a new entry, those should be (and many of them already have been) fixed.

There are certain DNS providers which really only allow one TXT record on a domain. This is really odd and you should probably contact your DNS provider and ask them
to fix this.

If for whatever reason you can't switch DNS providers and your DNS provider only supports one TXT record and doesn't want to fix that you could try splitting your
certificate into multiple certificates and add a sleep in the `deploy_cert` hook.
If you can't do that or really don't want to please leave a comment on https://github.com/lukas2511/dehydrated/issues/554,
if many people are having this unfixable problem I might try to implement a workaround.
