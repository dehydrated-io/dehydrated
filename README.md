# letsencrypt.sh

This is a client for signing certificates with an ACME-server (currently only provided by letsencrypt) implemented as a relatively simple shell-script.

It uses the `openssl` utility for everything related to actually handling keys and certificates, so you need to have that installed.

Other dependencies are (for now): curl, sed

Perl no longer is a dependency.
The only remaining perl code in this repository is the script you can use to convert your existing keyfile into something openssl (and this script) can read.

Current features:
- Signing of a list of domains
- Renewal if a certificate is about to expire

Please keep in mind that this software and even the acme-protocol are relatively young and may still have some unresolved issues.
Feel free to report any issues you find with this script or contribute by submitting a pullrequest.
