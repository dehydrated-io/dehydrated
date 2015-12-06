#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# default config values
CA="https://acme-v01.api.letsencrypt.org"
LICENSE="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"
HOOK_CHALLENGE=
RENEW_DAYS="14"
KEYSIZE="4096"
WELLKNOWN=".acme-challenges"

if [[ -e "config.sh" ]]; then
  . ./config.sh
fi

umask 077 # paranoid umask, we're creating private keys

anti_newline() {
  tr -d '\n\r'
}

urlbase64() {
  # urlbase64: base64 encoded string with '+' replaced with '-' and '/' replaced with '_'
  openssl base64 -e | anti_newline | sed -r 's/=*$//g' | tr '+/' '-_'
}

hex2bin() {
  # Store hex string from stdin
  tmphex="$(cat)"

  # Remove spaces
  hex=''
  for ((i=0; i<${#tmphex}; i+=1)); do
    test "${tmphex:$i:1}" == " " || hex="${hex}${tmphex:$i:1}"
  done

  # Add leading zero
  test $((${#hex} & 1)) == 0 || hex="0${hex}"

  # Convert to escaped string
  escapedhex=''
  for ((i=0; i<${#hex}; i+=2)); do
    escapedhex=$escapedhex\\x${hex:$i:2}
  done

  # Convert to binary data
  printf "${escapedhex}"
}

_request() {
  temperr="$(mktemp)"
  if [[ "${1}" = "head" ]]; then
    curl -sSf -I "${2}" 2> "${temperr}"
  elif [[ "${1}" = "get" ]]; then
    curl -sSf "${2}" 2> "${temperr}"
  elif [[ "${1}" = "post" ]]; then
    curl -sSf "${2}" -d "${3}" 2> "${temperr}"
  fi

  if [[ -s "${temperr}" ]]; then
    echo "  + ERROR: An error occured while sending ${1}-request to ${2} ($(<"${temperr}"))" >&2
    rm -f "${temperr}"
    exit 1
  fi

  rm -f "${temperr}"
}

signed_request() {
  # Encode payload as urlbase64
  payload64="$(printf '%s' "${2}" | urlbase64)"

  # Retrieve nonce from acme-server
  nonce="$(_request head "${CA}/directory" | grep Replay-Nonce: | awk -F ': ' '{print $2}' | anti_newline)"

  # Build header with just our public key and algorithm information
  header='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}}'

  # Build another header which also contains the previously received nonce and encode it as urlbase64
  protected='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}, "nonce": "'"${nonce}"'"}'
  protected64="$(printf '%s' "${protected}" | urlbase64)"

  # Sign header with nonce and our payload with our private key and encode signature as urlbase64
  signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign private_key.pem | urlbase64)"

  # Send header + extended header + payload + signature to the acme-server
  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  _request post "${1}" "${data}"
}

sign_domain() {
  domain="${1}"
  altnames="${*}"
  echo "Signing domain ${1} (${*})..."

  # If there is no existing certificate directory we need a new private key
  if [[ ! -e "certs/${domain}" ]]; then
    mkdir -p "certs/${domain}"
    echo "  + Generating private key..."
    openssl genrsa -out "certs/${domain}/privkey.pem" "${KEYSIZE}" 2> /dev/null > /dev/null
  fi

  # Generate signing request config and the actual signing request
  SAN=""
  for altname in $altnames; do
    SAN+="DNS:${altname}, "
  done
  SAN="$(printf '%s' "${SAN}" | sed 's/,\s*$//g')"
  echo "  + Generating signing request..."
  openssl req -new -sha256 -key "certs/${domain}/privkey.pem" -out "certs/${domain}/cert.csr" -subj "/CN=${domain}/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=%s" "${SAN}")) > /dev/null

  # Request and respond to challenges
  for altname in $altnames; do
    # Ask the acme-server for new challenge token and extract them from the resulting json block
    echo "  + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA}/acme/new-authz" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}')"

    challenge_token="$(printf '%s\n' "${response}" | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"token":\s*"[^"]*"' | cut -d'"' -f4 | sed 's/[^A-Za-z0-9_\-]/_/g')"
    challenge_uri="$(printf '%s\n' "${response}" | grep -Eo '"challenges":[^\[]*\[[^]]*]' | sed 's/{/\n{/g' | grep 'http-01' | grep -Eo '"uri":\s*"[^"]*"' | cut -d'"' -f4)"

    if [[ -z "${challenge_token}" ]] || [[ -z "${challenge_uri}" ]]; then
      echo "  + Error: Can't retrieve challenges (${response})"
      exit 1
    fi

    # Challenge response consists of the challenge token and the thumbprint of our public certificate
    keyauth="${challenge_token}.${thumbprint}"

    # Store challenge response in well-known location and make world-readable (so that a webserver can access it)
    printf '%s' "${keyauth}" > "${WELLKNOWN}/${challenge_token}"
    chmod a+r "${WELLKNOWN}/${challenge_token}"

    # Wait for hook script to deploy the challenge if used
    if [ -n "${HOOK_CHALLENGE}" ]; then
        ${HOOK_CHALLENGE} "${WELLKNOWN}/${challenge_token}" "${keyauth}"
    fi

    # Ask the acme-server to verify our challenge and wait until it becomes valid
    echo "  + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}')"

    status="$(printf '%s\n' "${result}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"
    if [[ ! "${status}" = "pending" ]] && [[ ! "${status}" = "valid" ]]; then
      echo "  + Challenge is invalid! (${result})"
      exit 1
    fi

    while [[ "${status}" = "pending" ]]; do
      status="$(_request get "${challenge_uri}" | grep -Eo '"status":\s*"[^"]*"' | cut -d'"' -f4)"
      sleep 1
    done

    echo "  + Challenge is valid!"
  done

  # Finally request certificate from the acme-server and store it in cert-${timestamp}.pem and link from cert.pem
  echo "  + Requesting certificate..."
  timestamp="$(date +%s)"
  csr64="$(openssl req -in "certs/${domain}/cert.csr" -outform DER | urlbase64)"
  crt64="$(signed_request "${CA}/acme/new-cert" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | openssl base64 -e)"
  printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "${crt64}" > "certs/${domain}/cert-${timestamp}.pem"
  rm -f "certs/${domain}/cert.pem"
  ln -s "cert-${timestamp}.pem" "certs/${domain}/cert.pem"
  echo "  + Done!"
}

# Check if private key exists, if it doesn't exist yet generate a new one (rsa key)
register="0"
if [[ ! -e "private_key.pem" ]]; then
  echo "+ Generating account key..."
  openssl genrsa -out "private_key.pem" "${KEYSIZE}" 2> /dev/null > /dev/null
  register="1"
fi

# Get public components from private key and calculate thumbprint
pubExponent64="$(printf "%06x" "$(openssl rsa -in private_key.pem -noout -text | grep publicExponent | head -1 | cut -d' ' -f2)" | hex2bin | urlbase64)"
pubMod64="$(printf '%s' "$(openssl rsa -in private_key.pem -noout -modulus | cut -d'=' -f2)" | hex2bin | urlbase64)"

thumbprint="$(printf '%s' "$(printf '%s' '{"e":"'"${pubExponent64}"'","kty":"RSA","n":"'"${pubMod64}"'"}' | shasum -a 256 | awk '{print $1}')" | hex2bin | urlbase64)"

# If we generated a new private key in the step above we have to register it with the acme-server
if [[ "${register}" = "1" ]]; then
  echo "+ Registering account key with letsencrypt..."
  signed_request "${CA}/acme/new-reg" '{"resource": "new-reg", "agreement": "'"$LICENSE"'"}' > /dev/null
fi

if [[ ! -e "domains.txt" ]]; then
  echo "You have to create a domains.txt file listing the domains you want certificates for. Have a look at domains.txt.example."
  exit 1
fi

if [[ ! -e "${WELLKNOWN}" ]]; then
  mkdir -p "${WELLKNOWN}"
fi

# Generate certificates for all domains found in domain.txt. Check if existing certificate are about to expire
<domains.txt sed 's/^\s*//g;s/\s*$//g' | grep -v '^#' | grep -v '^$' | while read -r line; do
  domain="$(echo $line | cut -d' ' -f1)"
  if [[ -e "certs/${domain}/cert.pem" ]]; then
    echo -n "Found existing cert for ${domain}. Expire date ..."
    set +e; openssl x509 -checkend $((${RENEW_DAYS} * 86400)) -noout -in "certs/${domain}/cert.pem"; expiring=$?; set -e
    if [[ ${expiring} -eq 0 ]]; then
        echo " is not within ${RENEW_DAYS} days. Skipping"
        continue
    fi
    echo " is within ${RENEW_DAYS} days. Renewing..."
  fi

  sign_domain $line
done
