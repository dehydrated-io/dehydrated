#!/usr/bin/env bash

cat >&2 << EOF
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! letsencrypt.sh has been renamed to dehydrated !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

Due to trademark violation letsencrypt.sh had to be renamed and is know called dehydrated.

To make a clean cut dehydrated doesn't use the old config locations /etc/letsencrypt.sh and
/usr/local/etc/letsencrypt.sh anymore, also the script file has been renamed.

If you were using the default WELLKNOWN location please also update your webserver to use /var/www/dehydrated.

You are currently running (or reading) a temporary wrapper which handles the old config locations,
you should update your setup to use /etc/dehydrated and the 'dehydrated' script file as soon as possible.

Script execution will continue in 10 seconds.
EOF

sleep 10

# parse given arguments for config
tmpargs=("${@}")
CONFIG=
CONFIGARG=
while (( ${#} )); do
  case "${1}" in
    --config|-f)
      shift 1
      CONFIGARG="${1}"
      ;;
    *)
      shift 1
      ;;
  esac
done
set -- "${tmpargs[@]}"

# look for default config locations
if [[ -z "${CONFIGARG:-}" ]]; then
  for check_config in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${SCRIPTDIR}"; do
    if [[ -f "${check_config}/config" ]]; then
      CONFIG="${check_config}/config"
      break
    fi
  done
fi

# find dehydrated script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

# add water
if [[ -n "${CONFIG:-}" ]]; then
	"${DIR}/dehydrated" --config "${CONFIG}" "${@}"
else
	"${DIR}/dehydrated" "${@}"
fi
