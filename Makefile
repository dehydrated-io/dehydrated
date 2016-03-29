
install:
	mkdir -p $(DESTDIR)/usr/bin
	install -m 755 letsencrypt.sh $(DESTDIR)/usr/bin/letsencrypt-sh
	mkdir -p $(DESTDIR)/etc/letsencrypt.sh
	install -m 755 docs/examples/hook.sh.example $(DESTDIR)/etc/letsencrypt.sh/hook.sh
	install -m 644 docs/examples/config.sh.debian $(DESTDIR)/etc/letsencrypt.sh/config.sh
	install -m 644 docs/examples/domains.txt.example $(DESTDIR)/etc/letsencrypt.sh/domains.txt.example
	mkdir -p $(DESTDIR)/var/lib/letsencryptsh/acme-challenges

