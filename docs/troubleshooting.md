# Troubleshooting

Generally if the following information doesn't provide a solution to your problem please take a look at existing issues (search for keywords) before creating a new one.

## "No registration exists matching provided key"

You probably changed from staging-CA to production-CA (or the other way).

Currently letsencrypt.sh doesn't detect a missing registration on the selected CA,
the current workaround is to move `private_key.pem` (and, if you care, `private_key.json`) out of the way so the scripts generates and registers a new one.

This will hopefully be fixed in the future.

## "Provided agreement URL [LICENSE1] does not match current agreement URL [LICENSE2]"

Set LICENSE in your config to the value in place of "LICENSE2".

LICENSE1 and LICENSE2 are just placeholders for the real values in this troubleshooting document!

## "Error creating new cert :: Too many certificates already issued for: [...]"

This is not an issue with letsencrypt.sh but an API limit with letsencrypt.

At the time of writing this you can only create 5 certificates per domain in a sliding window of 7 days.

## "Certificate request has 123 names, maximum is 100."

This also is an API limit from letsencrypt, you are requesting to sign a certificate with way too many domains.

## Invalid challenges

There are a few factors that could result in invalid challenges.

If you are using http validation make sure that the path you have configured with WELLKNOWN is readable under your domain.

To test this create a file (e.g. `test.txt`) in that directory and try opening it with your browser: `http://example.org/.well-known/acme-challenge/test.txt`.

If you get any error you'll have to fix your webserver configuration.
