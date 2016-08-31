#!/bin/bash

#use this line to force renewal. USE WITH CAUTION /root/letsencrypt.sh/letsencrypt.sh -c -f config.sh -x -k /root/letsencrypt.sh/ns-letsencrypt/ns-hook.sh
/root/letsencrypt.sh/letsencrypt.sh -c -f /root/letsencrypt.sh/config.sh -k /root/letsencrypt.sh/ns-letsencrypt/ns-hook.sh
/root/letsencrypt.sh/letsencrypt.sh -gc -f /root/letsencrypt.sh/config.sh
