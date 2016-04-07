# letsencrypt.sh for QNAP units

## Common Installation

Alter the config.sh to enable a configuration directory
```
CONFIG_D=${SCRIPTDIR}/config.d
```

Place the following two files in the config.d/ directory
  * `qnap_cabundle.sh` - installs CA certificates so that curl validation works
  * `qnap_mktemp.sh` - implements the full mktemp functionality with qnap's stub

Place the DNS names for your QNAP unit on a single line in `domains.txt`
```
echo "qnap.example.com nas.example.com" > domains.txt
```

## DNS Validation

Recommended: This validation requires you to make changes to your DNS.
It does not require exposing your QNAP device to Internet traffic,
therefore it is the higher-security approach.

The script will provide instructions on what changes to make to DNS.
It is up to you to make these changes. You'll need to rerun this script
and revalidate every 90 days to renew your certificate.

### Installation

Place the following file in the hook/ directory
  * `qnap-dns01-stunnel-install.sh`

## HTTP Validation

If you are willing to expose your QNAP to internet traffic for validation purposes,
you can enable HTTP validation. This is not recommended for security reasons, but
does allow for automatic renewal by running the script from cron.

### Installation

Place the following file in the config.d/ directory
  * `qnap_web_validation.sh`

Place the following file in the hook/ directory
  * `qnap-http01-stunnel-install.sh`
