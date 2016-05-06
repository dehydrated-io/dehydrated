#!/bin/bash

#use this line to force renewal. USE WITH CAUTION /root/letsencrypt.sh/letsencrypt.sh -c -x -k /root/letsencrypt.sh/ns-letsencrypt/ns-hook.sh
/root/letsencrypt.sh/letsencrypt.sh -c -x -k /root/letsencrypt.sh/ns-letsencrypt/ns-hook.sh
/root/letsencrypt.sh/letsencrypt.sh -gc
