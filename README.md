# letsencrypt.sh [![Build Status](https://travis-ci.org/lukas2511/letsencrypt.sh.svg?branch=master)](https://travis-ci.org/lukas2511/letsencrypt.sh)

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)]( )

This is a client for signing certificates with an ACME-server (currently only provided by letsencrypt) implemented as a relatively simple bash-script.

It uses the `openssl` utility for everything related to actually handling keys and certificates, so you need to have that installed.

Other dependencies are: curl, sed, grep, mktemp (all found on almost any system, curl being the only exception)

Current features:
- Signing of a list of domains
- Signing of a CSR
- Renewal if a certificate is about to expire or SAN (subdomains) changed
- Certificate revocation

If you want to import existing keys from the official letsencrypt client have a look at [Import from official letsencrypt client](https://github.com/lukas2511/letsencrypt.sh/wiki/Import-from-official-letsencrypt-client).

**Please note that you should use the staging URL when testing so as not to hit rate limits.** See the [Staging](#staging) section, below.

Please keep in mind that this software and even the acme-protocol are relatively young and may still have some unresolved issues.
Feel free to report any issues you find with this script or contribute by submitting a pullrequest.

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
 --privkey (-p) path/to/key.pem   Use specified private key instead of account key (useful for revocation)
 --config (-f) path/to/config.sh  Use specified config file
 --hook (-k) path/to/hook.sh      Use specified script for hooks
 --challenge (-t) http-01|dns-01  Which challenge should be used? Currently http-01 and dns-01 are supported
 --algo (-a) rsa|prime256v1|secp384r1 Which public key algorithm should be used? Supported: rsa, prime256v1 and secp384r1
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

This script uses `http-01`-type verification (for now) so you need to have that directory available over normal http (redirect to https will be acceptable).

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

### Staging

Let’s Encrypt has stringent rate limits in place during the public beta period. If you start testing using the production endpoint (which is the default), you will quickly hit these limits and find yourself locked out. To avoid this, please set the CA property to the Let’s Encrypt staging server URL in your `config.sh` file:

```bash
CA="https://acme-staging.api.letsencrypt.org/directory"
```

### dns-01 challenge

This script also supports the new `dns-01`-type verification. This type of verification requires you to be able to create a specific `TXT` DNS record for each hostname included in the certificate.

You need a hook script that deploys the challenge to your DNS server!

The hook script (indicated in the config.sh file or the --hook/-k command line argument) gets four arguments: an operation name (clean_challenge, deploy_challenge, or deploy_cert) and some operands for that. For deploy_challenge $2 is the domain name for which the certificate is required, $3 is a "challenge token" (which is not needed for dns-01), and $4 is a token which needs to be inserted in a TXT record for the domain.

Typically, you will need to split the subdomain name in two, the subdomain name and the domain name separately. For example, for "my.example.com", you'll need "my" and "example.com" separately. You then have to prefix "_acme-challenge." before the subdomain name, as in "_acme-challenge.my" and set a TXT record for that on the domain (e.g. "example.com") which has the value supplied in $4

```
_acme-challenge    IN    TXT    $4
_acme-challenge.my IN    TXT    $4
```

That could be done manually (as most providers don't have a DNS API), by having your hook script echo $1, $2 and $4 and then wait (read -s -r -e < /dev/tty) - give it a little time to get into their DNS system. Usually providers give you a boxes to put "_acme-challenge.my" and the token value in, and a dropdown to choose the record type, TXT. 

Or when you do have a DNS API, pass the details accordingly to achieve the same thing.

You can delete the TXT record when called with operation clean_challenge, when $2 is also the domain name.

Here are some examples: [Examples for DNS-01 hooks](https://github.com/lukas2511/letsencrypt.sh/wiki/Examples-for-DNS-01-hooks)

### Elliptic Curve Cryptography (ECC)

This script also supports certificates with Elliptic Curve public keys! Be aware that at the moment this is not available on the production servers from letsencrypt. Please read https://community.letsencrypt.org/t/ecdsa-testing-on-staging/8809/ for the current state of ECC support.
