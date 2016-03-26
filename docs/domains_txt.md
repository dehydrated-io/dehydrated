### domains.txt

letsencrypt.sh uses the file `domains.txt` as configuration for which certificates should be requested.

The file should have the following format:

```text
example.com www.example.com
example.net www.example.net wiki.example.net
```

This states that there should be two certificates `example.com` and `example.net`,
with the other domains in the corresponding line being their alternative names.
