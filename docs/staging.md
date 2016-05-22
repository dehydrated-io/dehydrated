# Staging

Let’s Encrypt has stringent rate limits in place during the public beta period.

If you start testing using the production endpoint (which is the default),
you will quickly hit these limits and find yourself locked out.

To avoid this, please set the CA property to the Let’s Encrypt staging server URL in your config file:

```bash
CA="https://acme-staging.api.letsencrypt.org/directory"
```

Please keep in mind that at the time of writing this letsencrypt.sh doesn't have support for registration management,
so if you change CA you'll have to move your `private_key.pem` (and, if you care, `private_key.json`) out of the way.
