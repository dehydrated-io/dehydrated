# dehydrated [![Build Status](https://travis-ci.org/lukas2511/dehydrated.svg?branch=master)](https://travis-ci.org/lukas2511/dehydrated)

![](docs/logo.jpg)

*Note: This project was renamed from letsencrypt.sh because the original name was violating Let's Encrypts trademark policy. I know that this results in quite a lot of installations failing but I didn't have a choice... For now there is a wrapper script for compatibility with old config locations and symlinks, but it will be removed in a few weeks.*

This is a client for signing certificates with an ACME-server.
Currently only provided Let's Encrypt provides them.

Current features:
- Signing of a list of domains
- Signing of a CSR
- Renewal if a certificate is about to expire or SAN (subdomains) changed
- Certificate revocation

Please keep in mind that this software and even the acme-protocol are relatively young and may still have some unresolved issues. Feel free to report any issues you find with this script or contribute by submitting a pull request.

dehydrated is implemented as a relatively simple bash script.

Dependencies:
- bash (it's a bash script..)
- openssl (required for key and certificate management) 
- cURL (file transfer utility)
- sed
- grep
- mktemp



### Getting started

For getting started, look at:
- [docs/domains_txt.md](docs/domains_txt.md), 
- [docs/wellknown.md](docs/wellknown.md), 
- [docs/examples/config](docs/examples/config) and 
- [Usage](#usage) section on this page. The `-c` option may be all you need.

Generally you want to:
- edit a copy of the docs/example/config file to set up your WELLKNOWN (or SERVERROOT) path, reference your domains.txt file etc, and 
- populate domains.txt with the server domains.

**Please note that you should use the staging URL when experimenting with this script to not hit Let's Encrypt's rate limits.** See [docs/staging.md](docs/staging.md).

If you have any problems take a look at our [Troubleshooting](docs/troubleshooting.md) guide.

## Usage:

```text
Usage: ./dehydrated [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...

Default command: help

Commands:
 --cron (-c)                      Sign/renew non-existant/changed/expiring certificates.
 --signcsr (-s) path/to/csr.pem   Sign a given CSR, output CRT on stdout (advanced usage)
 --revoke (-r) path/to/cert.pem   Revoke specified certificate
 --cleanup (-gc)                  Move unused certificate files to archive directory
 --help (-h)                      Show help text
 --env (-e)                       Output configuration variables for use in other scripts

Parameters:
 --full-chain (-fc)               Print full chain when using --signcsr
 --ipv4 (-4)                      Resolve names to IPv4 addresses only
 --ipv6 (-6)                      Resolve names to IPv6 addresses only
 --domain (-d) domain.tld         Use specified domain name(s) instead of domains.txt entry (one certificate!)
 --keep-going (-g)                Keep going after encountering an error while creating/renewing multiple certificates in cron mode
 --force (-x)                     Force renew of certificate even if it is longer valid than value in RENEW_DAYS
 --no-lock (-n)                   Don't use lockfile (potentially dangerous!)
 --ocsp                           Sets option in CSR indicating OCSP stapling to be mandatory
 --privkey (-p) path/to/key.pem   Use specified private key instead of account key (useful for revocation)
 --config (-f) path/to/config     Use specified config file
 --hook (-k) path/to/hook.sh      Use specified script for hooks
 --out (-o) certs/directory       Output certificates into the specified directory
 --challenge (-t) http-01|dns-01  Which challenge should be used? Currently http-01 and dns-01 are supported
 --algo (-a) rsa|prime256v1|secp384r1 Which public key algorithm should be used? Supported: rsa, prime256v1 and secp384r1
```
