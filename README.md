# dehydrated [![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=23P9DSJBTY7C8)

![](docs/logo.png)

Dehydrated is a client for signing certificates with an ACME-server (e.g. Let's Encrypt) implemented as a relatively simple (zsh-compatible) bash-script.
This client supports both ACME v1 and the new ACME v2 including support for wildcard certificates!

It uses the `openssl` utility for everything related to actually handling keys and certificates, so you need to have that installed.

Other dependencies are: cURL, sed, grep, awk, mktemp (all found pre-installed on almost any system, cURL being the only exception).

Current features:
- Signing of a list of domains (including wildcard domains!)
- Signing of a custom CSR (either standalone or completely automated using hooks!)
- Renewal if a certificate is about to expire or defined set of domains changed
- Certificate revocation
- and lots more..

Please keep in mind that this software, the ACME-protocol and all supported CA servers out there are relatively young and there might be a few issues. Feel free to report any issues you find with this script or contribute by submitting a pull request,
but please check for duplicates first (feel free to comment on those to get things rolling).

## Getting started

For getting started I recommend taking a look at [docs/domains_txt.md](docs/domains_txt.md), [docs/wellknown.md](docs/wellknown.md) and the [Usage](#usage) section on this page (you'll probably only need the `-c` option).

Generally you want to set up your WELLKNOWN path first, and then fill in domains.txt.

**Please note that you should use the staging URL when experimenting with this script to not hit Let's Encrypt's rate limits.** See [docs/staging.md](docs/staging.md).

If you have any problems take a look at our [Troubleshooting](docs/troubleshooting.md) guide.

## Config

dehydrated is looking for a config file in a few different places, it will use the first one it can find in this order:

- `/etc/dehydrated/config`
- `/usr/local/etc/dehydrated/config`
- The current working directory of your shell
- The directory from which dehydrated was run

Have a look at [docs/examples/config](docs/examples/config) to get started, copy it to e.g. `/etc/dehydrated/config`
and edit it to fit your needs.

## Usage:

```text
Usage: ./dehydrated [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...

Default command: help

Commands:
 --version (-v)                   Print version information
 --display-terms                  Display current terms of service
 --register                       Register account key
 --account                        Update account contact information
 --cron (-c)                      Sign/renew non-existent/changed/expiring certificates.
 --signcsr (-s) path/to/csr.pem   Sign a given CSR, output CRT on stdout (advanced usage)
 --revoke (-r) path/to/cert.pem   Revoke specified certificate
 --deactivate                     Deactivate account
 --cleanup (-gc)                  Move unused certificate files to archive directory
 --cleanup-delete (-gcd)          Deletes (!) unused certificate files
 --help (-h)                      Show help text
 --env (-e)                       Output configuration variables for use in other scripts

Parameters:
 --accept-terms                   Accept CAs terms of service
 --full-chain (-fc)               Print full chain when using --signcsr
 --ipv4 (-4)                      Resolve names to IPv4 addresses only
 --ipv6 (-6)                      Resolve names to IPv6 addresses only
 --domain (-d) domain.tld         Use specified domain name(s) instead of domains.txt entry (one certificate!)
 --ca url/preset                  Use specified CA URL or preset
 --alias certalias                Use specified name for certificate directory (and per-certificate config) instead of the primary domain (only used if --domain is specified)
 --keep-going (-g)                Keep going after encountering an error while creating/renewing multiple certificates in cron mode
 --force (-x)                     Force renew of certificate even if it is longer valid than value in RENEW_DAYS
 --force-validation               Force revalidation of domain names (used in combination with --force)
 --no-lock (-n)                   Don't use lockfile (potentially dangerous!)
 --lock-suffix example.com        Suffix lockfile name with a string (useful for with -d)
 --ocsp                           Sets option in CSR indicating OCSP stapling to be mandatory
 --privkey (-p) path/to/key.pem   Use specified private key instead of account key (useful for revocation)
 --domains-txt path/to/domains.txt Use specified domains.txt instead of default/configured one
 --config (-f) path/to/config     Use specified config file
 --hook (-k) path/to/hook.sh      Use specified script for hooks
 --preferred-chain issuer-cn      Use alternative certificate chain identified by issuer CN
 --out (-o) certs/directory       Output certificates into the specified directory
 --alpn alpn-certs/directory      Output alpn verification certificates into the specified directory
 --challenge (-t) http-01|dns-01|tls-alpn-01 Which challenge should be used? Currently http-01, dns-01, and tls-alpn-01 are supported
 --algo (-a) rsa|prime256v1|secp384r1 Which public key algorithm should be used? Supported: rsa, prime256v1 and secp384r1
```
