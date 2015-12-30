#!/usr/bin/env bash

# if certifate issued successfully, restart nginx
if [[ "$1" == "deploy_cert" ]]; then
    /usr/sbin/service nginx restart
fi
