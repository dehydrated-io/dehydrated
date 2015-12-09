#!/bin/bash

#
# Deploy letsencrypt certificates via ssh.
#
# Use in conjunction with "ssh_filter_letsencrypt.sh".
#

set -e
set -u
set -o pipefail

declare -A rsh

### config section ###

rsh[example.org]="ssh -i /etc/ssh/id_rsa.letsencrypt letsencrypt@example.org"
rsh[www.example.org]="ssh -i /etc/ssh/id_rsa.letsencrypt letsencrypt@example.org"

### end config section ###


command=$1
echo " * ssh_hook.sh: $command"

case $command in
  deploy_challenge|clean_challenge)
    altname=$2
    ${rsh[$altname]} $@
    ;;
  deploy_cert)
    domain=$2
    privkey=$3
    cert=$4
    fullchain=$5
    cat $privkey | ${rsh[$domain]} deploy_privkey $domain
    cat $cert | ${rsh[$domain]} deploy_cert $domain
    cat $fullchain | ${rsh[$domain]} deploy_fullchain $domain
    ;;
  *)
    echo "illegal command" >&2
    exit 1
    ;;
esac

exit 0
