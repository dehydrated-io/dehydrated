#!/bin/bash

set -e

source config.sh

urlbase64() {
  base64 -w 0 | sed -r 's/=*$//g' | tr '+/' '-_'
}

signed_request() {
  payload64="$(echo -n "${2}" | urlbase64)"

  nonce="$(curl -s -I ${CA}/directory | grep Replay-Nonce | awk -F ': ' '{print $2}' | tr -d '\n\r')"

  header='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}}'

  protected='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}, "nonce": "'"${nonce}"'"}'
  protected64="$(echo -n "${protected}" | urlbase64)"

  signed64="$(echo -n "${protected64}.${payload64}" | openssl dgst -sha256 -sign private_key.pem | urlbase64)"

  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  curl -s -d "${data}" "${1}"
}

sign_domain() {
  domain="${1}"
  altnames="${@}"
  echo "Signing domain ${1} (${@})..."
  if [ ! -e "certs/${domain}" ]; then
    SAN=""
    for altname in $altnames; do
      SAN+="DNS:${altname}, "
    done
    SAN="$(echo -n $SAN | sed 's/,\s*$//g')"

    mkdir "certs/${domain}"

    echo "  + Generating private key..."
    openssl genrsa -out "certs/${domain}/privkey.pem" 4096 2> /dev/null > /dev/null
    echo "  + Generating signing request..."
    openssl req -new -sha256 -key "certs/${domain}/privkey.pem" -out "certs/${domain}/cert.csr" -subj "/CN=${domain}/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=${SAN}")) > /dev/null
  fi

  for altname in $altnames; do
    echo "  + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA}/acme/new-authz" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}')"

    challenge_token="$(echo $response | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"token":\s*"[^"]*"' | cut -d'"' -f4 | sed 's/[^A-Za-z0-9_\-]/_/g')"
    challenge_uri="$(echo $response | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"uri":\s*"[^"]*"' | cut -d'"' -f4)"

    keyauth="${challenge_token}.${thumbprint}"

    echo -n "${keyauth}" > "${WELLKNOWN}/${challenge_token}"

    echo "  + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}')"

    status="$(echo "${result}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"

    if [ ! "${status}" = "pending" ] && [ ! "${status}" = "valid" ]; then
      echo "  + Challenge is invalid! (${result})"
      exit 1
    fi

    while [ ! "${status}" = "valid" ]; do
      status="$(curl -s "${challenge_uri}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"
    done

    echo "  + Challenge is valid!"
  done

  echo "  + Requesting certificate..."
  csr64="$(openssl req -in "certs/${domain}/cert.csr" -outform DER | urlbase64)"
  crt64="$(signed_request "${CA}/acme/new-cert" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | base64 -w 64)"
  echo -e "-----BEGIN CERTIFICATE-----\n${crt64}\n-----END CERTIFICATE-----\n" > "certs/${domain}/cert.pem"
  echo "  + Done!"
}

register="0"
if [ ! -e "private_key.pem" ]; then
  echo "+ Generating account key..."
  openssl genrsa -out "private_key.pem" 4096 2> /dev/null > /dev/null
  register="1"
fi

pubExponent64="$(printf "%06x" "$(openssl rsa -in private_key.pem -noout -text | grep publicExponent | head -1 | cut -d' ' -f2)" | perl -pe 's/([0-9a-f]{2})/chr hex $1/gie' | urlbase64)"
pubMod64="$(echo -n "$(openssl rsa -in private_key.pem -noout -modulus | cut -d'=' -f2 | perl -pe 's/([0-9a-f]{2})/chr hex $1/gie')" | urlbase64)"

thumbprint="$(echo -n "$(echo -n '{"e":"'"${pubExponent64}"'","kty":"RSA","n":"'"${pubMod64}"'"}' | sha256sum | awk '{print $1}' | perl -pe 's/([0-9a-f]{2})/chr hex $1/gie')" | urlbase64)"

if [ "${register}" = "1" ]; then
  echo "+ Registering account key with letsencrypt..."
  signed_request "${CA}/acme/new-reg" '{"resource": "new-reg", "agreement": "https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"}' > /dev/null
fi

cat domains.txt | sed 's/^\s*//g;s/\s*$//g' | grep -v '^#' | grep -v '^$' | while read line; do
  sign_domain $line
done
