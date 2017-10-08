# Config on per-certificate base

dehydrated allows a few configuration variables to be set on a per-certificate base.

To use this feature create a `config` file in the certificates output directory (e.g. `certs/example.org/config`).

If `DOMAINS_D` is set, the respective file name is the name of the certificate, inside `DOMAINS_D`
(e.g. if `DOMAINS_D=/etc/dehydrated/domains.d`, then a certificate for the domain `example.org` will
use additional configuration parameters from `/etc/dehydrated/domains.d/example.org`). If the certificate
is generated from an alias name, then this name forms the file name.

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
