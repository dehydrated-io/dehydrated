#!/usr/bin/env bash

set -e
set -u
set -o pipefail

# Get the directory in which this script is stored
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default config values
CA="https://acme-v01.api.letsencrypt.org/directory"
LICENSE="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"
HOOK=
RENEW_DAYS="14"
KEYSIZE="4096"
WELLKNOWN="${SCRIPTDIR}/.acme-challenges"
PRIVATE_KEY_RENEW="no"
BASEDIR="${SCRIPTDIR}"
OPENSSL_CNF="$(openssl version -d | cut -d'"' -f2)/openssl.cnf"
ROOTCERT="lets-encrypt-x1-cross-signed.pem"
CONTACT_EMAIL=

# Check for config in various locations
CONFIG=""
for check_config in "${SCRIPTDIR}" "${HOME}/.letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "/etc/letsencrypt.sh" "${PWD}"; do
  if [[ -e "${check_config}/config.sh" ]]; then
    BASEDIR="${check_config}"
    CONFIG="${check_config}/config.sh"
    break
  fi
done

if [[ -z "${CONFIG}" ]]; then
  echo "WARNING: No config file found, using default config!"
  sleep 2
else
  echo "Using config file ${CONFIG}"
  # shellcheck disable=SC1090
  . "${CONFIG}"
fi

# Remove slash from end of BASEDIR. Mostly for cleaner outputs, doesn't change functionality.
BASEDIR="${BASEDIR%%/}"

umask 077 # paranoid umask, we're creating private keys

# Export some environment variables to be used in hook script
export WELLKNOWN
export BASEDIR
export CONFIG

anti_newline() {
  tr -d '\n\r'
}

urlbase64() {
  # urlbase64: base64 encoded string with '+' replaced with '-' and '/' replaced with '_'
  openssl base64 -e | anti_newline | sed 's/=*$//g' | tr '+/' '-_'
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
  printf -- "${escapedhex}"
}

get_json_string_value() {
  grep -Eo '"'"${1}"'":\s*"[^"]*"' | cut -d'"' -f4
}

get_json_array() {
  grep -Eo '"'"${1}"'":[^\[]*\[[^]]*]'
}

_request() {
  tempcont="$(mktemp)"

  if [[ "${1}" = "head" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -I)"
  elif [[ "${1}" = "get" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}")"
  elif [[ "${1}" = "post" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -d "${3}")"
  fi

  if [[ ! "${statuscode:0:1}" = "2" ]]; then
    echo "  + ERROR: An error occurred while sending ${1}-request to ${2} (Status ${statuscode})" >&2
    echo >&2
    echo "Details:" >&2
    echo "$(<"${tempcont}"))" >&2
    rm -f "${tempcont}"

    # Wait for hook script to clean the challenge if used
    if [[ -n "${HOOK}" ]] && [[ -n "${challenge_token:+set}"  ]]; then
      ${HOOK} "clean_challenge" '' "${challenge_token}" "${keyauth}"
    fi

    exit 1
  fi

  cat  "${tempcont}"
  rm -f "${tempcont}"
}
_output_on_error() {
  # Only way to capture the output and exit code is to disable set -e.
  set +e
  out="$("$@" 2>&1)"
  res=$?
  set -e
  if [[ $res -ne 0 ]]; then
    echo "  + ERROR: failed to run $* (Exitcode: $res)" >&2
    echo >&2
    echo "Details:" >&2
    echo "$out" >&2
    exit $res
  fi
}
# OpenSSL writes to stderr/stdout even when there are no errors. So just
# display the output if the exit code was != 0 to simplify debugging.
_openssl() {
    _output_on_error openssl "$@"
}

signed_request() {
  # Encode payload as urlbase64
  payload64="$(printf '%s' "${2}" | urlbase64)"

  # Retrieve nonce from acme-server
  nonce="$(_request head "${CA}" | grep Replay-Nonce: | awk -F ': ' '{print $2}' | anti_newline)"

  # Build header with just our public key and algorithm information
  header='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}}'

  # Build another header which also contains the previously received nonce and encode it as urlbase64
  protected='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}, "nonce": "'"${nonce}"'"}'
  protected64="$(printf '%s' "${protected}" | urlbase64)"

  # Sign header with nonce and our payload with our private key and encode signature as urlbase64
  signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign "${BASEDIR}/private_key.pem" | urlbase64)"

  # Send header + extended header + payload + signature to the acme-server
  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  _request post "${1}" "${data}"
}

revoke_cert() {
  if [ -z "${CA_REVOKE_CERT}" ]; then
    echo " + ERROR: Certificate authority doesn't allow certificate revocation."
    exit 1
  fi
  cert="${1}"
  cert64="$(openssl x509 -in "${cert}" -inform PEM -outform DER | urlbase64)"
  response="$(signed_request "${CA_REVOKE_CERT}" '{"resource": "revoke-cert", "certificate": "'"${cert64}"'"}')"
  # if there is a problem with our revoke request _request (via signed_request) will report this and "exit 1" out
  # so if we are here, it is safe to assume the request was successful
  echo " + SUCCESS"
  echo " + renaming certificate to ${cert}-revoked"
  mv -f "${cert}" "${cert}-revoked"
}

sign_domain() {
  domain="${1}"
  altnames="${*}"
  echo " + Signing domains..."
  if [[ -z "${CA_NEW_AUTHZ}" ]] || [[ -z "${CA_NEW_CERT}" ]]; then
    echo " + ERROR: Certificate authority doesn't allow certificate signing"
    exit 1
  fi
  timestamp="$(date +%s)"

  # If there is no existing certificate directory => make it
  if [[ ! -e "${BASEDIR}/certs/${domain}" ]]; then
    echo " + make directory ${BASEDIR}/certs/${domain} ..."
    mkdir -p "${BASEDIR}/certs/${domain}"
  fi

  privkey="privkey.pem"
  # generate a new private key if we need or want one
  if [[ ! -f "${BASEDIR}/certs/${domain}/privkey.pem" ]] || [[ "${PRIVATE_KEY_RENEW}" = "yes" ]]; then
    echo " + Generating private key..."
    privkey="privkey-${timestamp}.pem"
    _openssl genrsa -out "${BASEDIR}/certs/${domain}/privkey-${timestamp}.pem" "${KEYSIZE}"
  fi

  # Generate signing request config and the actual signing request
  SAN=""
  for altname in $altnames; do
    SAN+="DNS:${altname}, "
  done
  SAN="${SAN%%, }"
  echo " + Generating signing request..."
  openssl req -new -sha256 -key "${BASEDIR}/certs/${domain}/${privkey}" -out "${BASEDIR}/certs/${domain}/cert-${timestamp}.csr" -subj "/CN=${domain}/" -reqexts SAN -config <(cat "${OPENSSL_CNF}" <(printf "[SAN]\nsubjectAltName=%s" "${SAN}"))

  # Request and respond to challenges
  for altname in $altnames; do
    # Ask the acme-server for new challenge token and extract them from the resulting json block
    echo " + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA_NEW_AUTHZ}" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}')"

    challenges="$(printf '%s\n' "${response}" | get_json_array challenges)"
    repl=$'\n''{' # fix syntax highlighting in Vim
    challenge="$(printf "%s" "${challenges//\{/${repl}}" | grep 'http-01')"
    challenge_token="$(printf '%s' "${challenge}" | get_json_string_value token | sed 's/[^A-Za-z0-9_\-]/_/g')"
    challenge_uri="$(printf '%s' "${challenge}" | get_json_string_value uri)"

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
    if [[ -n "${HOOK}" ]]; then
        ${HOOK} "deploy_challenge" "${altname}" "${challenge_token}" "${keyauth}"
    fi

    # Ask the acme-server to verify our challenge and wait until it becomes valid
    echo " + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}')"

    status="$(printf '%s\n' "${result}" | get_json_string_value status)"

    # get status until a result is reached => not pending anymore
    while [[ "${status}" = "pending" ]]; do
      sleep 1
      status="$(_request get "${challenge_uri}" | get_json_string_value status)"
    done

    rm -f "${WELLKNOWN}/${challenge_token}"

    if [[ "${status}" = "valid" ]]; then
      echo " + Challenge is valid!"
    else
      echo " + Challenge is invalid! (returned: ${status})"

      # Wait for hook script to clean the challenge if used
      if [[ -n "${HOOK}" ]] && [[ -n "${challenge_token}" ]]; then
        ${HOOK} "clean_challenge" "${altname}" "${challenge_token}" "${keyauth}"
      fi

      exit 1
    fi

  done

  # Finally request certificate from the acme-server and store it in cert-${timestamp}.pem and link from cert.pem
  echo " + Requesting certificate..."
  csr64="$(openssl req -in "${BASEDIR}/certs/${domain}/cert-${timestamp}.csr" -outform DER | urlbase64)"
  crt64="$(signed_request "${CA_NEW_CERT}" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | openssl base64 -e)"
  crt_path="${BASEDIR}/certs/${domain}/cert-${timestamp}.pem"
  printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "${crt64}" > "${crt_path}"
  # try to load the certificate to detect corruption
  echo " + Checking certificate..." >&2
  _openssl x509 -text < "${crt_path}"

  # Create fullchain.pem
  if [[ -e "${BASEDIR}/certs/${ROOTCERT}" ]] || [[ -e "${SCRIPTDIR}/certs/${ROOTCERT}" ]]; then
    echo " + Creating fullchain.pem..."
    cat "${crt_path}" > "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"
    if [[ -e "${BASEDIR}/certs/${ROOTCERT}" ]]; then
      cat "${BASEDIR}/certs/${ROOTCERT}" >> "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"
    else
      cat "${SCRIPTDIR}/certs/${ROOTCERT}" >> "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"
    fi
    ln -sf "fullchain-${timestamp}.pem" "${BASEDIR}/certs/${domain}/fullchain.pem"
  fi

  # Update remaining symlinks
  if [ ! "${privkey}" = "privkey.pem" ]; then
    ln -sf "privkey-${timestamp}.pem" "${BASEDIR}/certs/${domain}/privkey.pem"
  fi

  ln -sf "cert-${timestamp}.csr" "${BASEDIR}/certs/${domain}/cert.csr"
  ln -sf "cert-${timestamp}.pem" "${BASEDIR}/certs/${domain}/cert.pem"

  # Wait for hook script to clean the challenge and to deploy cert if used
  if [[ -n "${HOOK}" ]]; then
      ${HOOK} "deploy_cert" "${domain}" "${BASEDIR}/certs/${domain}/privkey.pem" "${BASEDIR}/certs/${domain}/cert.pem" "${BASEDIR}/certs/${domain}/fullchain.pem"
  fi

  unset challenge_token
  echo " + Done!"
}


LOCKFILE="${BASEDIR}/lock"
remove_lock() {
    if [[ -n "${LOCKFILE}" ]]; then
        rm -f "${LOCKFILE}"
    fi
}
trap 'remove_lock' EXIT

# Use lock file to prevent concurrent access.
set -o noclobber
if ! { date > "${LOCKFILE}"; } 2>/dev/null; then
    echo "  + ERROR: Lock file '${LOCKFILE}' present, aborting." >&2
    LOCKFILE= # so remove_lock doesn't remove it
    exit 1
fi
set +o noclobber


# Get CA URLs
CA_DIRECTORY="$(_request get "${CA}")"
CA_NEW_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-cert)"
CA_NEW_AUTHZ="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-authz)"
CA_NEW_REG="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-reg)"
CA_REVOKE_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value revoke-cert)"

# Check if private key exists, if it doesn't exist yet generate a new one (rsa key)
register="0"
if [[ ! -e "${BASEDIR}/private_key.pem" ]]; then
  echo "+ Generating account key..."
  _openssl genrsa -out "${BASEDIR}/private_key.pem" "${KEYSIZE}"
  register="1"
fi

# Get public components from private key and calculate thumbprint
pubExponent64="$(printf "%06x" "$(openssl rsa -in "${BASEDIR}/private_key.pem" -noout -text | grep publicExponent | head -1 | cut -d' ' -f2)" | hex2bin | urlbase64)"
pubMod64="$(printf '%s' "$(openssl rsa -in "${BASEDIR}/private_key.pem" -noout -modulus | cut -d'=' -f2)" | hex2bin | urlbase64)"

thumbprint="$(printf '%s' "$(printf '%s' '{"e":"'"${pubExponent64}"'","kty":"RSA","n":"'"${pubMod64}"'"}' | shasum -a 256 | awk '{print $1}')" | hex2bin | urlbase64)"

# If we generated a new private key in the step above we have to register it with the acme-server
if [[ "${register}" = "1" ]]; then
  echo "+ Registering account key with letsencrypt..."
  if [ -z "${CA_NEW_REG}" ]; then
    echo " + ERROR: Certificate authority doesn't allow registrations."
    exit 1
  fi
  # if an email for the contact has been provided then adding it to the registration request
  if [[ -n "${CONTACT_EMAIL}" ]]; then
    signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "contact":["mailto:'"${CONTACT_EMAIL}"'"], "agreement": "'"$LICENSE"'"}' > /dev/null
  else
    signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "agreement": "'"$LICENSE"'"}' > /dev/null
  fi
fi

if [[ -e "${BASEDIR}/domains.txt" ]]; then
  DOMAINS_TXT="${BASEDIR}/domains.txt"
elif [[ -e "${SCRIPTDIR}/domains.txt" ]]; then
  DOMAINS_TXT="${SCRIPTDIR}/domains.txt"
else
  echo "You have to create a domains.txt file listing the domains you want certificates for. Have a look at domains.txt.example."
  exit 1
fi

if [[ ! -e "${WELLKNOWN}" ]]; then
  mkdir -p "${WELLKNOWN}"
fi

# revoke certificate by user request
if [[ "${1:-}" = "revoke" ]]; then
  if [[ -z "{2:-}" ]] || [[ ! -f "${2}" ]]; then
    echo "Usage: ${0} revoke path/to/cert.pem"
    exit 1
  fi

  echo "Revoking ${2}"
  revoke_cert "${2}"

  exit 0
fi

# Generate certificates for all domains found in domains.txt. Check if existing certificate are about to expire
<"${DOMAINS_TXT}" sed 's/^\s*//g;s/\s*$//g' | grep -v '^#' | grep -v '^$' | while read -r line; do
  domain="$(printf '%s\n' "${line}" | cut -d' ' -f1)"
  cert="${BASEDIR}/certs/${domain}/cert.pem"

  echo "Processing ${domain}"
  if [[ -e "${cert}" ]]; then
    echo " + Found existing cert..."

    valid="$(openssl x509 -enddate -noout -in "${cert}" | cut -d= -f2- )"

    echo -n " + Valid till ${valid} "
    if openssl x509 -checkend $((RENEW_DAYS * 86400)) -noout -in "${cert}"; then
      echo "(Longer than ${RENEW_DAYS} days). Skipping!"
      continue
    fi
    echo "(Less than ${RENEW_DAYS} days). Renewing!"
  fi

  # shellcheck disable=SC2086
  sign_domain $line
done
