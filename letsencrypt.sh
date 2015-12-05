#!/bin/bash

set -e
set -u
set -o pipefail

. ./config.sh

umask 077 # paranoid umask, we're creating private keys


urlbase64() {
  base64 -w 0 | sed -r 's/=*$//g' | tr '+/' '-_'
}

hex2bin() {
  tmphex="$(cat)"

  # remove spaces
  hex=''
  for ((i=0; i<${#tmphex}; i+=1)); do
    test "${tmphex:$i:1}" == " " || hex="${hex}${tmphex:$i:1}"
  done

  # add leading zero
  test $((${#hex} & 1)) == 0 || hex="0${hex}"

  # convert to escaped string
  escapedhex=''
  for ((i=0; i<${#hex}; i+=2)); do
    escapedhex=$escapedhex\\x${hex:$i:2}
  done

  printf "${escapedhex}"
}

_request() {
  temperr="$(mktemp)"
  if [ "${1}" = "head" ]; then
    curl -sSf -I "${2}" 2>${temperr}
  elif [ "${1}" = "get" ]; then
    curl -sSf "${2}" 2>${temperr}
  elif [ "${1}" = "post" ]; then
    curl -sSf "${2}" -d "${3}" 2>${temperr}
  fi
  if [ ! -z "$(<${temperr})" ]; then echo "  + ERROR: An error occured while sending ${1}-request to ${2} ($(<"${temperr}"))" >&2; exit 1; fi
  rm -f "${temperr}"
}

signed_request() {
  payload64="$(printf '%s' "${2}" | urlbase64)"

  # -sSf: stay silent but report errors and exit with != 0 if they occur
  nonce="$(_request head "${CA}/directory" | grep Replay-Nonce: | awk -F ': ' '{print $2}' | tr -d '\n\r')"

  header='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}}'

  protected='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}, "nonce": "'"${nonce}"'"}'
  protected64="$(printf '%s' "${protected}" | urlbase64)"

  signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign private_key.pem | urlbase64)"

  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  _request post "${1}" "${data}"
}

sign_domain() {
  domain="${1}"
  altnames="${*}"
  echo "Signing domain ${1} (${*})..."
  if [ ! -e "certs/${domain}" ]; then
    SAN=""
    for altname in $altnames; do
      SAN+="DNS:${altname}, "
    done
    SAN="$(printf '%s' "${SAN}" | sed 's/,\s*$//g')"

    mkdir "certs/${domain}"

    echo "  + Generating private key..."
    openssl genrsa -out "certs/${domain}/privkey.pem" 4096 2> /dev/null > /dev/null
    echo "  + Generating signing request..."
    openssl req -new -sha256 -key "certs/${domain}/privkey.pem" -out "certs/${domain}/cert.csr" -subj "/CN=${domain}/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=%s" "${SAN}")) > /dev/null
  fi

  for altname in $altnames; do
    echo "  + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA}/acme/new-authz" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}')"

    challenge_token="$(printf '%s\n' "${response}" | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"token":\s*"[^"]*"' | cut -d'"' -f4 | sed 's/[^A-Za-z0-9_\-]/_/g')"
    challenge_uri="$(printf '%s\n' "${response}" | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"uri":\s*"[^"]*"' | cut -d'"' -f4)"

    if [ -z "${challenge_token}" ] || [ -z "${challenge_uri}" ]; then
      echo "  + Error: Can't retrieve challenges (${response})"
      exit 1
    fi

    keyauth="${challenge_token}.${thumbprint}"

    printf '%s' "${keyauth}" > "${WELLKNOWN}/${challenge_token}"
    chmod a+r "${WELLKNOWN}/${challenge_token}"

    echo "  + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}')"

    status="$(printf '%s\n' "${result}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"

    if [ ! "${status}" = "pending" ] && [ ! "${status}" = "valid" ]; then
      echo "  + Challenge is invalid! (${result})"
      exit 1
    fi

    while [ ! "${status}" = "valid" ]; do
      status="$(_request get "${challenge_uri}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"
    done

    echo "  + Challenge is valid!"
  done

  echo "  + Requesting certificate..."
  csr64="$(openssl req -in "certs/${domain}/cert.csr" -outform DER | urlbase64)"
  crt64="$(signed_request "${CA}/acme/new-cert" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | base64 -w 64)"
  printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "${crt64}" > "certs/${domain}/cert.pem"
  echo "  + Done!"
}

register="0"
if [ ! -e "private_key.pem" ]; then
  echo "+ Generating account key..."
  openssl genrsa -out "private_key.pem" 4096 2> /dev/null > /dev/null
  register="1"
fi

pubExponent64="$(printf "%06x" "$(openssl rsa -in private_key.pem -noout -text | grep publicExponent | head -1 | cut -d' ' -f2)" | hex2bin | urlbase64)"
pubMod64="$(printf '%s' "$(openssl rsa -in private_key.pem -noout -modulus | cut -d'=' -f2)" | hex2bin | urlbase64)"

thumbprint="$(printf '%s' "$(printf '%s' '{"e":"'"${pubExponent64}"'","kty":"RSA","n":"'"${pubMod64}"'"}' | sha256sum | awk '{print $1}')" | hex2bin | urlbase64)"

if [ "${register}" = "1" ]; then
  echo "+ Registering account key with letsencrypt..."
  signed_request "${CA}/acme/new-reg" '{"resource": "new-reg", "agreement": "https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"}' > /dev/null
fi

<domains.txt sed 's/^\s*//g;s/\s*$//g' | grep -v '^#' | grep -v '^$' | while read line; do
  sign_domain "$line"
done
