# WELLKNOWN

Let's Encrypt (or the ACME-protocol in general) is checking if you are in control of a domain by accessing a file under a path similar to `http://example.org/.well-known/acme-challenge/c3VjaC1jaGFsbGVuZ2UtbXVjaA-aW52YWxpZC13b3c`.

`http-01`-type verification (default in this script, there is also support for [dns based verification](dns-verification.md)) so you need to have that directory available over normal http (redirect to https will be acceptable, but you definitively have to be able to access the http url!).

letsencrypt.sh has a config variable called `WELLKNOWN`, which corresponds to the directory which should be served under `/.well-known/acme-challenge` on your domain.

An example config would be to create a directory `/var/www/letsencrypt`, set `WELLKNOWN=/var/www/letsencrypt`.

After configuration the WELLKNOWN directory you'll need to add an alias to your webserver configuration pointing to that path:

## Nginx example config

```nginx
server {
  [...]
  location /.well-known/acme-challenge {
    alias /var/www/letsencrypt;
  }
  [...]
}
```

## Apache example config

```apache
Alias /.well-known/acme-challenge /var/www/letsencrypt

<Directory /var/www/letsencrypt>
        Options None
        AllowOverride None
        Order allow,deny
        Allow from all
</Directory>
```
