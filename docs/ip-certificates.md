## IP Certificates

In addition to issuing certificates for domain names, the ACME protocol also supports certificates
for IP addresses. Dehydrated has included support for IP identifiers for quite some time, but this
feature only became practically useful once Let’s Encrypt made IP certificate issuance publicly
available.

IP certificates can be helpful in scenarios where a service is accessed directly via an address
rather than a hostname, for example in internal networks, appliances, temporary systems, or
environments without reliable DNS.

### Limitations and requirements

Currently, there are a few important constraints to be aware of:

- Validation is only possible using http-01 challenges. This means you must have a web server publicly reachable on the IP address you want to certify.
- Let's Encrypt only issues IP certificates via the shortlived ACME profile. Certificates issued through this profile are currently valid for 7 days.

Because of the short lifetime, it’s important to renew these certificates frequently and adjust
any automated jobs accordingly.

### Preparing an IP certificate in dehydrated

For convenience, create the certificate directory and a per-certificate configuration file in advance.

Example for an IPv6 address:

```bash
ip="2001:0db8:0:3::1337"
```

Or for IPv4:

```bash
ip="224.13.37.42"
```

Then set up the certificate directory and configuration and add the ip to domains.txt:

```bash
# Create certificate directory
mkdir -p "certs/ip:${ip}"

# Use the shortlived ACME profile for this certificate
echo "ACME_PROFILE=shortlived" >> "certs/ip:${ip}/config"

# Renew this certificate every 4 days
echo "RENEW_DAYS=4" >> "certs/ip:${ip}/config"

# Add IP to domains.txt
echo ip:${ip} >> domains.txt
```

Keep in mind that you also can use aliases for better readability in your directory structure.
See the `domains.txt` documentation for more information.

### Requesting the certificate

Once the directory and configuration are in place, you can request and renew the certificate as usual:

```bash
dehydrated -c
```

Dehydrated will automatically include the IP identifier and use the configured ACME profile.

### Renewal considerations

Since short-lived certificates expire after one week, make sure that:

- Your renewal job runs frequently enough (for example daily or every few days)
- Monitoring or alerting accounts for the much shorter validity period
- Failing to renew in time will result in expired certificates much sooner than with standard domain certificates.

### IPv6 address normalization

To ensure compatibility with Let's Encrypt's seemingly somewhat non-standard handling of IP identifiers,
dehydrated internally normalizes IPv6 addresses before using them as certificate names.

This process first expands and reformats IPv6 notation into a consistent representation, eliminating
shorthand forms such as :: compression. Afterwards it re-shortens the IPv6 address in a way that is
accepted by Let's Encrypt. Doing so guarantees that:

- IPv6 addresses are compatible with Let's Encrypt
- Matching of existing and configured identifiers works, without dependency on special formatting in domains.txt

This happens internally and should be invisible to most users, but if you are running this against
a custom ACME server you might want to be aware of this behaviour.

Example formatting:

- Original IPv6 address: `2001:db8:0:3:0:0:0:1337` (not accepted by Let's Encrypt)
- Fully expanded IPv6 address: `2001:0db8:0000:0003:0000:0000:0000:1337` (also not accepted)
- Re-shortened IPv6 address: `2001:db8:0:3::1337` (gets accepted)



