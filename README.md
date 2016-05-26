# letsencrypt.sh [![Build Status](https://travis-ci.org/lukas2511/letsencrypt.sh.svg?branch=master)](https://travis-ci.org/lukas2511/letsencrypt.sh)

This is a client for signing certificates with an ACME-server (currently only provided by letsencrypt) implemented as a relatively simple bash-script.

It uses the `openssl` utility for everything related to actually handling keys and certificates, so you need to have that installed.

Other dependencies are: curl, sed, grep, mktemp (all found on almost any system, curl being the only exception)

Current features:
- Signing of a list of domains
- Signing of a CSR
- Renewal if a certificate is about to expire or SAN (subdomains) changed
- Certificate revocation

Please keep in mind that this software and even the acme-protocol are relatively young and may still have some unresolved issues.
Feel free to report any issues you find with this script or contribute by submitting a pullrequest.

### Getting started

For getting started I recommend taking a look at [docs/domains_txt.md](docs/domains_txt.md), [docs/wellknown.md](docs/wellknown.md) and the [Usage](#usage) section on this page (you'll probably only need the `-c` option).

Generally you want to set up your WELLKNOWN path first, and then fill in domains.txt.

**Please note that you should use the staging URL when experimenting with this script to not hit letsencrypts rate limits.** See [docs/staging.md](docs/staging.md).

If you have any problems take a look at our [Troubleshooting](docs/troubleshooting.md) guide.

## Usage:

```text
Usage: ./letsencrypt.sh [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...

Default command: help

Commands:
 --cron (-c)                      Sign/renew non-existant/changed/expiring certificates.
 --signcsr (-s) path/to/csr.pem   Sign a given CSR, output CRT on stdout (advanced usage)
 --revoke (-r) path/to/cert.pem   Revoke specified certificate
 --cleanup (-gc)                  Move unused certificate files to archive directory
 --help (-h)                      Show help text
 --env (-e)                       Output configuration variables for use in other scripts

Parameters:
 --domain (-d) domain.tld         Use specified domain name(s) instead of domains.txt entry (one certificate!)
 --force (-x)                     Force renew of certificate even if it is longer valid than value in RENEW_DAYS
 --ocsp                           Sets option in CSR indicating OCSP stapling to be mandatory
 --privkey (-p) path/to/key.pem   Use specified private key instead of account key (useful for revocation)
 --config (-f) path/to/config     Use specified config file
 --hook (-k) path/to/hook.sh      Use specified script for hooks
 --out (-o) certs/directory       Output certificates into the specified directory
 --challenge (-t) http-01|dns-01  Which challenge should be used? Currently http-01 and dns-01 are supported
 --algo (-a) rsa|prime256v1|secp384r1 Which public key algorithm should be used? Supported: rsa, prime256v1 and secp384r1
```
