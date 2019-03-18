# Config on per-certificate base

dehydrated allows a few configuration variables to be set on a per-certificate base.

To use this feature create a `config` file in the certificates output directory (e.g. `certs/example.org/config`).

Currently supported options:

- PRIVATE_KEY_RENEW
- PRIVATE_KEY_ROLLOVER
- KEY_ALGO
- KEYSIZE
- OCSP_MUST_STAPLE
- CHALLENGETYPE
- HOOK
- HOOK_CHAIN
- WELLKNOWN
- OPENSSL_CNF
- RENEW_DAYS

## DOMAINS_D

If `DOMAINS_D` is set, dehydrated will use it for your per-certificate configurations.
Instead of `certs/example.org/config` it will look for a configuration under `DOMAINS_D/example.org`.

If an alias is set, it will be used instead of the primary domain name.
