#!/usr/bin/env bash

DIR=$(cd $(dirname $0) && pwd);

$DIR/letsencrypt.sh \
    --cron \
    --challenge dns-01 \
    --hook "$DIR/hooks/cloudflare/hook.py" \
    --out "/etc/secure/converge/"
