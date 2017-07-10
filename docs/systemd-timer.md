### Systemd timers

##Separate certificate stores

Situation: One server, one domain, multiple services.
For example, let $SERVICE be one of : 
- nginx 
- postfix 
- ejabberd

Each service requires its own SSL certificate potentially with different parameters.

Create the following folder(s):
`/etc/ssl/$SERVICE/`


each $SERVICE contains its own domains.txt, hooks.sh, and per domain certificate store.
Now $SERVICE may depend on `letsencrypt@$SERVICE.timer` to automatically update its certificates by
adding `Wants=letsencrypt@$SERVICE.timer` to the [UNIT] section.

##Unit files
#letsencrypt@.service
```
[Unit]
Description=%I Let's Encrypt certificate checker

[Service]
Type=oneshot
ExecStart=/usr/bin/dehydrated --out /etc/ssl/%I --lock-suffix %I --hook /etc/ssl/%I/hook.sh -D /etc/ssl/%I/domains.txt -c
```

#letsencrypt@.timer
```
[Unit]
Description=Refresh let's %I encrypt certificates

[Timer]
Persistent=true
OnCalendar=monthly
```
