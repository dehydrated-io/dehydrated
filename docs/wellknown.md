# WELLKNOWN

`http-01`-type verification is default in this script.
There is also support for [dns based verification](dns-verification.md)).

Let's Encrypt or any other certificate provider (using ACME-protocol) 
will require validation for any (sub-)domain you want to sign a certificate for.
An acme server verifies if you are in control of a domain 
by accessing a verification file called a "token".
A token is referenced via a URL similar to 
`http://example.org/.well-known/acme-challenge/t0k3n-fil3name`.  


The verification URL uses normal HTTP on port 80.
Redirect to HTTPS will work, but starting point is always HTTP.

dehydrated uses a config variable called `WELLKNOWN` to locate the token. 
WELLKNOWN is set to the full file system directory path of the verification file:
${WELLKNOWN}/token-filename

The acme standard is in flux.
Currently, the directory path of the token URL is fixed to `/.well-known/acme-challenge/`.
You can read more about this in dehydrated's config file comments.

To ease configuration, the dehydration file provides variable: SERVERROOT.
Set SERVERROOT to the fullpath of the web server's root directory.
As an example, for apache, the serverroot may be '/var/www'.
In which case, add a line like this to dehydrated's config file:
 `SERVERROOT=/var/www/`

If you are specifying the token location to dehydrated as an argument, use WELLKNOWN instead of SERVERROOT;
SERVERROOT is ignored.

Continuing the example, set WELLKNOWN something like this:
`WELLKNOWN=/var/www/.well-known/acme-challenge`.
Remember to append the fixed directory path '.well-known/acme-challenge'

If the server configuration is more complex, look at the example below.

## Example Usage


If you have more than one serverroot, 
or the server is behind a reverse proxy or load balanced,
the configuration above won't work.  
However, a few additional lines of webserver configuration may be all that is needed.

For example create a directory `/var/www/dehydrated` and set `WELLKNOWN=/var/www/dehydrated` in the scripts config.

You'll need to configure aliases on your Webserver:

### Nginx example config

With Nginx you'll need to add this to any of your `server`/VHost config blocks:

```nginx
server {
  [...]
  location /.well-known/acme-challenge {
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
