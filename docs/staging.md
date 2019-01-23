# Staging

Let’s Encrypt has stringent rate limits in place.

If you start testing using the production endpoint (which is the default),
you will quickly hit these limits and find yourself locked out.

To avoid this, please set the CA property to the Let’s Encrypt staging server URL in your config file:

```bash
CA="https://acme-staging.api.letsencrypt.org/directory"
```

# ACMEv2 staging

You can use `CA="https://acme-staging-v02.api.letsencrypt.org/directory"` to test dehydrated with
the ACMEv2 staging endpoint.
