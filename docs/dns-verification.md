### dns-01 challenge

This script also supports the new `dns-01`-type verification. This type of verification requires you to be able to create a specific `TXT` DNS record for each hostname included in the certificate.

You need a hook script that deploys the challenge to your DNS server.

The hook script (indicated in the config file or the `--hook/-k` command line argument) gets four arguments:

$1 an operation name (`clean_challenge`, `deploy_challenge`, `deploy_cert`, `invalid_challenge` or `request_failure`) and some operands for that.
For `deploy_challenge` 

$2 is the domain name for which the certificate is required, 

$3 is a "challenge token" (which is not needed for dns-01), and 

$4 is a token which needs to be inserted in a TXT record for the domain.

Typically, you will need to split the subdomain name in two, the subdomain name and the domain name separately. For example, for "my.example.com", you'll need "my" and "example.com" separately. You then have to prefix "_acme-challenge." before the subdomain name, as in "_acme-challenge.my" and set a TXT record for that on the domain (e.g. "example.com") which has the value supplied in $4

```
_acme-challenge    IN    TXT    $4
_acme-challenge.my IN    TXT    $4
```

That could be done manually (as most providers don't have a DNS API), by having your hook script echo $1, $2 and $4 and then wait (`read -s -r -e < /dev/tty`) - give it a little time to get into their DNS system. Usually providers give you a boxes to put "_acme-challenge.my" and the token value in, and a dropdown to choose the record type, TXT. 

Or when you do have a DNS API, pass the details accordingly to achieve the same thing.

You can delete the TXT record when called with operation `clean_challenge`, when $2 is also the domain name.

Here are some examples: [Examples for DNS-01 hooks](https://github.com/dehydrated-io/dehydrated/wiki)
