### domains.txt

dehydrated uses the file `domains.txt` as configuration for which certificates should be requested.

The file should have the following format:

```text
example.com www.example.com
example.net www.example.net wiki.example.net
example.net www.example.net wiki.example.net > certalias
```

This states that there should be two certificates `example.com` and `example.net`,
with the other domains in the corresponding line being their alternative names.

You can define an alias for your certificate which will (instead of the primary domain) be
used as directory name under your certdir and for a per-certificate lookup.
This allows multiple certificates with identical sets of domains but different configuration
to exist.
