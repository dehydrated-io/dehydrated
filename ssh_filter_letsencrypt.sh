#!/bin/bash

#
# Use on webserver, in conjunction with ssh_hook.sh, either as
# "ForceCommand" in "sshd_config", or in "authorized_keys".
#
# Example line in "authorized_keys" file:
#
#   from="192.168.0.42",command="/home/letsencrypt/ssh_filter_letsencrypt.sh --log",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding <pubkey>...
#

declare -A challenge_dir key_file cert_file fullchain_file

### config section ###

challenge_dir[example.org]="/var/www/www.example.org/htdocs/.well-known/acme-challenge"
challenge_dir[www.example.org]="/var/www/www.example.org/htdocs/.well-known/acme-challenge"

key_file[example.org]="/etc/ssl/apache2/example.org/privkey.pem"
cert_file[example.org]="/etc/ssl/apache2/example.org/cert.pem"
fullchain_file[example.org]="/etc/ssl/apache2/example.org/fullchain.pem"

### end config section ###


set -e
set -u
set -o pipefail

enable_log=

log_cmd()
{
  if [[ -n "$enable_log" ]]; then
    logger -p $1 -t ssh_filter_letsencrypt.sh "$2 (Name: ${LOGNAME:-<unknown>}; Remote: ${SSH_CLIENT:-<unknown>})${3:+: $3}"
  fi
}

reject_and_die()
{
  local reason=$1
  log_cmd "auth.err" "REJECT" "$reason"
  echo "ERROR: ssh_filter_letsencrypt.sh: ssh command rejected: $reason" >&2
  exit 1
}


trap 'reject_and_die "script error"' EXIT

while [[ "$#" -ge 1 ]]; do
  key="$1"
  case $key in
    -l|--log)
      enable_log=1
      ;;
    *)
      echo "ERROR: ssh_filter_letsencrypt.sh: failed to parse command line option: $key" >&2
      exit 1
      ;;
  esac
  shift
done


case "$SSH_ORIGINAL_COMMAND" in
  *\$*)     reject_and_die "unsafe character"     ;;
  *\&*)     reject_and_die "unsafe character"     ;;
  *\(*)     reject_and_die "unsafe character"     ;;
  *\{*)     reject_and_die "unsafe character"     ;;
  *\;*)     reject_and_die "unsafe character"     ;;
  *\<*)     reject_and_die "unsafe character"     ;;
  *\>*)     reject_and_die "unsafe character"     ;;
  *\`*)     reject_and_die "unsafe character"     ;;
  *\|*)     reject_and_die "unsafe character"     ;;
  *\.\./*)  reject_and_die "directory traversal"  ;;
esac


array=($SSH_ORIGINAL_COMMAND)
command=${array[0]}

case $command in
  deploy_challenge)
    altname=${array[1]}
    challenge_token=${array[2]}
    keyauth=${array[3]}
    outdir=${challenge_dir[$altname]}
    echo -n "$keyauth" > ${outdir}/${challenge_token}
    ;;
  clean_challenge)
    altname=${array[1]}
    challenge_token=${array[2]}
    keyauth=${array[3]}
    outdir=${challenge_dir[$altname]}
    rm ${outdir}/${challenge_token}
    ;;
  deploy_privkey)
    domain=${array[1]}
    outfile=${key_file[$domain]}
    cat > ${outfile}
    ;;
  deploy_cert)
    domain=${array[1]}
    outfile=${cert_file[$domain]}
    cat > ${outfile}
    ;;
  deploy_fullchain)
    domain=${array[1]}
    outfile=${fullchain_file[$domain]}
    cat > ${outfile}
    ;;
  *)
    reject_and_die "illegal command"
    ;;
esac

log_cmd "auth.info" "$command"

echo " * ssh_filter_letsencrypt.sh: ${command}: success"

trap - EXIT
exit 0
