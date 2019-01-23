# WELLKNOWN

With `http-01`-type verification (default in this script, there is also support for [dns based verification](dns-verification.md)) Let's Encrypt (or the ACME-protocol in general) is checking if you are in control of a domain by accessing a verification file on an URL similar to `http://example.org/.well-known/acme-challenge/m4g1C-t0k3n`.  
It will do that for any (sub-)domain you want to sign a certificate for.

At the moment you'll need to have that location available over normal HTTP on port 80 (redirect to HTTPS will work, but starting point is always HTTP!).

dehydrated has a config variable called `WELLKNOWN`, which corresponds to the directory which should be served under `/.well-known/acme-challenge` on your domain. So in the above example the token would have been saved as `$WELLKNOWN/m4g1C-t0k3n`.

If you only have one docroot on your server you could easily do something like `WELLKNOWN=/var/www/.well-known/acme-challenge`, for anything else look at the example below.

## Example Usage

If you have more than one docroot (or you are using your server as a reverse proxy / load balancer) the simple configuration mentioned above wouldn't work, but with just a few lines of webserver configuration this can be solved.

An example would be to create a directory `/var/www/dehydrated` and set `WELLKNOWN=/var/www/dehydrated` in the scripts config.

You'll need to configure aliases on your Webserver:

### Nginx example config

With Nginx you'll need to add this to any of your `server`/VHost config blocks:

```nginx
server {
  [...]
  location ^~ /.well-known/acme-challenge {
    alias /var/www/dehydrated;
  }
  [...]
}
```

### Apache example config

With Apache just add this to your config and it should work in any VHost:

```apache
Alias /.well-known/acme-challenge /var/www/dehydrated

<Directory /var/www/dehydrated>
        Options None
        AllowOverride None

        # Apache 2.x
        <IfModule !mod_authz_core.c>
                Order allow,deny
                Allow from all
        </IfModule>

        # Apache 2.4
        <IfModule mod_authz_core.c>
                Require all granted
        </IfModule>
</Directory>
```

### Lighttpd example config

With Lighttpd just add this to your config and it should work in any VHost:

```lighttpd
server.modules += ("alias")
alias.url += (
 "/.well-known/acme-challenge/" => "/var/www/dehydrated/",
)
```


### Hiawatha example config

With Hiawatha just add an alias to your config file for each VirtualHost and it should work:
```hiawatha
VirtualHost {
    Hostname = example.tld subdomain.mywebsite.tld
    Alias = /.well-known/acme-challenge:/var/www/dehydrated
}
```
