# Staging and testing

Let’s Encrypt has stringent rate limits in place during the public beta period.

If you start testing using the production endpoint (which is the default),
you will quickly hit these limits and find yourself locked out.

For souch cases Let’s Encrypt provides staging server URL for testing and developement.

To use it, please apply `letsencrypt.sh` parameter `--testCA` for any command.

```bash
$ letsencryph configuration
#
# !! WARNING !! No main config file found, using default config!
#
declare -- CA="https://acme-staging.api.letsencrypt.org/directory"
declare -- LICENSE="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"
declare -- CHALLENGETYPE="http-01"
declare -- HOOK=""
declare -- HOOK_CHAIN="no"
declare -- RENEW_DAYS="30"
declare -- ACCOUNT_KEY="/opt/letsencrypt.sh/testCA_private_key.pem"
declare -- ACCOUNT_KEY_JSON="/opt/letsencrypt.sh/testCA_private_key.json"
declare -- KEYSIZE="4096"
declare -- WELLKNOWN="/opt/letsencrypt.sh/.acme-challenges"
declare -- PRIVATE_KEY_RENEW="yes"
declare -- OPENSSL_CNF="/usr/lib/ssl/openssl.cnf"
declare -- CONTACT_EMAIL=""
declare -- LOCKFILE="/opt/letsencrypt.sh/lock"
```

Please keep in mind that at the time of writing this letsencrypt.sh doesn't have support for registration management,
so if you use `--testCA` you'll have second pair of private key and json: `testCA_private_key.pem`, `testCA_private_key.json`.
