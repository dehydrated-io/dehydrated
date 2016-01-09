# letsencrypt.sh [![Build Status](https://travis-ci.org/lukas2511/letsencrypt.sh.svg?branch=master)](https://travis-ci.org/lukas2511/letsencrypt.sh)

This is a client for signing certificates with an ACME-server (currently only provided by letsencrypt) implemented as a relatively simple bash-script.

It uses the `openssl` utility for everything related to actually handling keys and certificates, so you need to have that installed.

Other dependencies are: curl, sed, grep, mktemp (all found on almost any system, curl being the only exception)

Current features:
- Signing of a list of domains
- Renewal if a certificate is about to expire or SAN (subdomains) changed
- Certificate revocation

If you want to import existing keys from the official letsencrypt client have a look at [Import from official letsencrypt client](https://github.com/lukas2511/letsencrypt.sh/wiki/Import-from-official-letsencrypt-client).

Please keep in mind that this software and even the acme-protocol are relatively young and may still have some unresolved issues.
Feel free to report any issues you find with this script or contribute by submitting a pullrequest.

## Usage:

```text
Usage: ./letsencrypt.sh [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...

Default command: help

Commands:
 --cron (-c)                      Sign/renew non-existant/changed/expiring certificates.
 --revoke (-r) path/to/cert.pem   Revoke specified certificate
 --help (-h)                      Show help text
 --env (-e)                       Output configuration variables for use in other scripts
 --cleanup (-gc)                  Remove old and not used files in certs directory

Parameters:
 --domain (-d) domain.tld         Use specified domain name(s) instead of domains.txt entry (one certificate!)
 --force (-x)                     Force renew of certificate even if it is longer valid than value in RENEW_DAYS
 --privkey (-p) path/to/key.pem   Use specified private key instead of account key (useful for revocation)
 --config (-f) path/to/config.sh  Use specified config file
 --hook (-k) path/to/hook.sh      Use specified script for hooks
 --challenge (-t) http-01|dns-01  Which challenge should be used? Currently http-01 and dns-01 are supported
```

### domains.txt

The file `domains.txt` should have the following format:

```text
example.com www.example.com
example.net www.example.net wiki.example.net
```

This states that there should be two certificates `example.com` and `example.net`,
with the other domains in the corresponding line being their alternative names.

### $WELLKNOWN / challenge-response

Boulder (acme-server) is looking for challenge responses under your domain in the `.well-known/acme-challenge` directory

This script uses `http-01`-type verification (for now) so you need to have that directory available over normal http (no ssl).

A full URL would look like `http://example.org/.well-known/acme-challenge/c3VjaC1jaGFsbGVuZ2UtbXVjaA-aW52YWxpZC13b3c`.

An example setup to get this to work would be:

nginx.conf:
```
...
location /.well-known/acme-challenge {
  alias /var/www/letsencrypt;
}
...
```

config.sh:
```bash
...
WELLKNOWN="/var/www/letsencrypt"
...
```

An alternative to setting the WELLKNOWN variable would be to create a symlink to the default location next to the script (or BASEDIR):
`ln -s /var/www/letsencrypt .acme-challenges`

### dns-01 challenge

This script also supports the new `dns-01`-type verification. Be aware that at the moment this is not available on the production servers from letsencrypt. Please read https://community.letsencrypt.org/t/dns-challenge-is-in-staging/8322 for the current state of `dns-01` support.

You need a hook script that deploys the challenge to your DNS server!
