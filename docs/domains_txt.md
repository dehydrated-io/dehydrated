### domains.txt

dehydrated uses the file `domains.txt` as configuration for which certificates should be requested.

The file should have the following format:

```text
example.com www.example.com
example.net www.example.net wiki.example.net
```

This states that there should be two certificates `example.com` and `example.net`,
with the other domains in the corresponding line being their alternative names.

Per default, the 'primary domain', which is the first name on the line, selects the
output directory under `CERTDIR` where key and certificate files for each entry are
written to. The domain-specific configuration file under `DOMAINS_D` or `CERTDIR/domain/config` 
also uses the primary domain. This works out nicely while all certificates have different
primary domain names. If multiple certificates should be generated for the same primary
domain, the respective lines in `domains.txt` can be prefixed with the target alias
name in the following form:

```text
--alias example-rsa example.com www.example.com
--alias example-ecdsa example.com www.example.com
```

Now the first certificate will look up its configuration settings in `DOMAINS_D/example-rsa`
or `CERTDIR/example-rsa/config`, and the output will be written to
`example-rsa` under `CERTDIR`. The second certificate can use different configuration
settings in the file `example-ecdsa`, and its output is written to the separate
directory `example-ecdsa` under `CERTDIR`.
