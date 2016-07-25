# Config on per-certificate base

letsencrypt.sh allows a few configuration variables to be set on a per-certificate base.

To use this feature create a `config` file in the certificates output directory (e.g. `certs/example.org/config`).

Currently supported options:

- PRIVATE_KEY_RENEW
- KEY_ALGO
- KEYSIZE
- OCSP_MUST_STAPLE
- CHALLENGETYPE
- HOOK
- HOOK_CHAIN
- WELLKNOWN
- OPENSSL_CNF
- RENEW_DAYS
