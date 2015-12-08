#!/bin/bash

set -e
set -u
set -o pipefail

umask 077 # paranoid umask, we're creating private keys

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASEDIR="${SCRIPTDIR}"
LETSENCRYPT="/etc/letsencrypt"

# shellcheck disable=SC1090
. "${SCRIPTDIR}/config.sh"

if [[ -e "${BASEDIR}/domains.txt" ]]; then
  DOMAINS_TXT="${BASEDIR}/domains.txt"
elif [[ -e "${SCRIPTDIR}/domains.txt" ]]; then
  DOMAINS_TXT="${SCRIPTDIR}/domains.txt"
else
  echo "You have to create a domains.txt file listing the domains you want certificates for. Have a look at domains.txt.example."
  echo "For the purpose of this import script the file can be empty, but it has to exist."
  exit 1
fi

for certdir in "${LETSENCRYPT}/live/"*; do
  domain="$(basename "${certdir}")"
  echo "Processing ${domain}"

  # Check if we already have a certificate for the same (main) domain
  if [ -e "${BASEDIR}/certs/${domain}" ]; then
    echo " + Skipping: Found existing certificate directory, don't want to delete anything."
    continue
  fi

  # Check if private-key, certificate and fullchain exist
  if [[ ! -e "${certdir}/privkey.pem" ]]; then
    echo " + Skipping: Private key is missing."
    continue
  fi
  if [[ ! -e "${certdir}/cert.pem" ]]; then
    echo " + Skipping: Certificate is missing."
    continue
  fi
  if [[ ! -e "${certdir}/fullchain.pem" ]]; then
    echo " + Skipping: Chain is missing."
    continue
  fi

  # Check if certificate still valid
  if ! openssl x509 -checkend 0 -noout -in "${certdir}/cert.pem" >/dev/null 2>&1; then
    echo " + Skipping: Certificate is expired."
    continue
  fi

  # Import certificate
  timestamp="$(date +%s)"

  echo " + Adding list of domains to ${DOMAINS_TXT}"
  SAN="$(openssl x509 -in "${certdir}/cert.pem" -noout -text | grep -A1 "Subject Alternative Name" | grep "DNS")"
  SAN="${SAN//DNS:/}"
  SAN="${SAN//, / }"
  altnames="${domain}"
  for altname in ${SAN}; do
    if [[ ! "${altname}" = "${domain}" ]]; then
      altnames="${altnames} ${altname}"
    fi
  done
  echo "${altnames}" >> "${DOMAINS_TXT}"

  mkdir -p "${BASEDIR}/certs/${domain}"

  echo " + Importing private key"
  cat "${certdir}/privkey.pem" > "${BASEDIR}/certs/${domain}/privkey-${timestamp}.pem"
  ln -s "privkey-${timestamp}.pem" "${BASEDIR}/certs/${domain}/privkey.pem"

  echo " + Importing certificate"
  cat "${certdir}/cert.pem" > "${BASEDIR}/certs/${domain}/cert-${timestamp}.pem"
  ln -s "cert-${timestamp}.pem" "${BASEDIR}/certs/${domain}/cert.pem"

  echo " + Importing chain"
  cat "${certdir}/fullchain.pem" > "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"
  ln -s "fullchain-${timestamp}.pem" "${BASEDIR}/certs/${domain}/fullchain.pem"
done
