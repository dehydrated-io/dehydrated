# TLS-ALPN-01

With `tls-alpn-01`-type verification Let's Encrypt (or the ACME-protocol in general) is checking if you are in control of a domain by accessing
your webserver using a custom ALPN and expecting a specially crafted TLS certificate containing a verification token.
It will do that for any (sub-)domain you want to sign a certificate for.

Dehydrated generates the required verification certificates, but the delivery is out of its scope.

### Example nginx config

On an nginx tcp load-balancer you can use the `ssl_preread` module to map a different port for acme-tls
requests than for e.g. HTTP/2 or HTTP/1.1 requests.

Your config should look something like this:

```nginx
stream {
  server {
    map $ssl_preread_alpn_protocols $tls_port {
      ~\bacme-tls/1\b 10443;
      default 443;
    }

    server {
      listen 443;
      listen [::]:443;
      proxy_pass 10.13.37.42:$tls_port;
      ssl_preread on;
    }
  }
}
```

That way https requests are forwarded to port 443 on the backend server, and acme-tls/1 requests are
forwarded to port 10443.

In the future nginx might support internal routing based on custom ALPNs, but for now you'll have to
use a custom responder for the alpn verification certificates (see below).

### Example responder

I hacked together a simple responder in Python, it might not be the best, but it works for me:

```python
#!/usr/bin/env python3

import ssl
import socketserver
import threading
import re
import os

ALPNDIR="/etc/dehydrated/alpn-certs"
PROXY_PROTOCOL=False

FALLBACK_CERTIFICATE="/etc/ssl/certs/ssl-cert-snakeoil.pem"
FALLBACK_KEY="/etc/ssl/private/ssl-cert-snakeoil.key"

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    pass

class ThreadedTCPRequestHandler(socketserver.BaseRequestHandler):
    def create_context(self, certfile, keyfile, first=False):
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.set_ciphers('ECDHE+AESGCM')
        ssl_context.set_alpn_protocols(["acme-tls/1"])
        ssl_context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
        if first:
            ssl_context.set_servername_callback(self.load_certificate)
        ssl_context.load_cert_chain(certfile=certfile, keyfile=keyfile)
        return ssl_context

    def load_certificate(self, sslsocket, sni_name, sslcontext):
        print("Got request for %s" % sni_name)
        if not re.match(r'^(([a-zA-Z]{1})|([a-zA-Z]{1}[a-zA-Z]{1})|([a-zA-Z]{1}[0-9]{1})|([0-9]{1}[a-zA-Z]{1})|([a-zA-Z0-9][-_.a-zA-Z0-9]{0,61}[a-zA-Z0-9]))\.([a-zA-Z]{2,13}|[a-zA-Z0-9-]{2,30}.[a-zA-Z]{2,3})$', sni_name):
            return

        certfile = os.path.join(ALPNDIR, "%s.crt.pem" % sni_name)
        keyfile = os.path.join(ALPNDIR, "%s.key.pem" % sni_name)

        if not os.path.exists(certfile) or not os.path.exists(keyfile):
            return

        sslsocket.context = self.create_context(certfile, keyfile)

    def handle(self):
        if PROXY_PROTOCOL:
            buf = b""
            while b"\r\n" not in buf:
                buf += self.request.recv(1)

        ssl_context = self.create_context(FALLBACK_CERTIFICATE, FALLBACK_KEY, True)
        newsock = ssl_context.wrap_socket(self.request, server_side=True)

if __name__ == "__main__":
    HOST, PORT = "0.0.0.0", 10443

    server = ThreadedTCPServer((HOST, PORT), ThreadedTCPRequestHandler, bind_and_activate=False)
    server.allow_reuse_address = True
    try:
        server.server_bind()
        server.server_activate()
        server.serve_forever()
    except:
        server.shutdown()
```
