#!/bin/bash

#UNCOMMENT to force renewal. USE WITH CAUTION /root/letsencrypt.sh/letsencrypt.sh -c -x
/root/letsencrypt.sh/letsencrypt.sh -c -x
/root/letsencrypt.sh/ns-letsencrypt/ns-copytons.py
/root/letsencrypt.sh/letsencrypt.sh -gc