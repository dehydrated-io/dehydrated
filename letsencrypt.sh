#!/usr/bin/env bash

# letsencrypt.sh by lukas2511
# Source: https://github.com/lukas2511/letsencrypt.sh
#
# This script is licensed under The MIT License (see LICENSE for more information).

set -e
set -u
set -o pipefail
[[ -n "${ZSH_VERSION:-}" ]] && set -o SH_WORD_SPLIT && set +o FUNCTION_ARGZERO
umask 077 # paranoid umask, we're creating private keys

# Find directory in which this script is stored by traversing all symbolic links
SOURCE="${0}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPTDIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

BASEDIR="${SCRIPTDIR}"

# Create (identifiable) temporary files
_mktemp() {
  # shellcheck disable=SC2068
  mktemp ${@:-} "${TMPDIR:-/tmp}/letsencrypt.sh-XXXXXX"
}

# Check for script dependencies
check_dependencies() {
  # just execute some dummy and/or version commands to see if required tools exist and are actually usable
  openssl version > /dev/null 2>&1 || _exiterr "This script requires an openssl binary."
  _sed "" < /dev/null > /dev/null 2>&1 || _exiterr "This script requires sed with support for extended (modern) regular expressions."
  command -v grep > /dev/null 2>&1 || _exiterr "This script requires grep."
  _mktemp -u > /dev/null 2>&1 || _exiterr "This script requires mktemp."
  diff -u /dev/null /dev/null || _exiterr "This script requires diff."

  # curl returns with an error code in some ancient versions so we have to catch that
  set +e
  curl -V > /dev/null 2>&1
  retcode="$?"
  set -e
  if [[ ! "${retcode}" = "0" ]] && [[ ! "${retcode}" = "2" ]]; then
    _exiterr "This script requires curl."
  fi
}

store_configvars() {
  __KEY_ALGO="${KEY_ALGO}"
  __OCSP_MUST_STAPLE="${OCSP_MUST_STAPLE}"
  __PRIVATE_KEY_RENEW="${PRIVATE_KEY_RENEW}"
  __KEYSIZE="${KEYSIZE}"
  __CHALLENGETYPE="${CHALLENGETYPE}"
  __HOOK="${HOOK}"
  __WELLKNOWN="${WELLKNOWN}"
  __HOOK_CHAIN="${HOOK_CHAIN}"
  __OPENSSL_CNF="${OPENSSL_CNF}"
  __RENEW_DAYS="${RENEW_DAYS}"
  __IP_VERSION="${IP_VERSION}"
}

reset_configvars() {
  KEY_ALGO="${__KEY_ALGO}"
  OCSP_MUST_STAPLE="${__OCSP_MUST_STAPLE}"
  PRIVATE_KEY_RENEW="${__PRIVATE_KEY_RENEW}"
  KEYSIZE="${__KEYSIZE}"
  CHALLENGETYPE="${__CHALLENGETYPE}"
  HOOK="${__HOOK}"
  WELLKNOWN="${__WELLKNOWN}"
  HOOK_CHAIN="${__HOOK_CHAIN}"
  OPENSSL_CNF="${__OPENSSL_CNF}"
  RENEW_DAYS="${__RENEW_DAYS}"
  IP_VERSION="${__IP_VERSION}"
}

# verify configuration values
verify_config() {
  if [[ "${COMMAND}" = "revoke" ]]; then
    return
  fi
  [[ "${CHALLENGETYPE}" =~ (http-01|dns-01) ]] || _exiterr "Unknown challenge type ${CHALLENGETYPE}... can not continue."
  if [[ "${CHALLENGETYPE}" = "dns-01" ]] && [[ -z "${HOOK}" ]]; then
    _exiterr "Challenge type dns-01 needs a hook script for deployment... can not continue."
  fi
  if [[ "${CHALLENGETYPE}" = "http-01" && ! -d "${WELLKNOWN}" ]]; then
    _exiterr "WELLKNOWN directory doesn't exist, please create ${WELLKNOWN} and set appropriate permissions."
  fi
  [[ "${KEY_ALGO}" =~ ^(rsa|prime256v1|secp384r1)$ ]] || _exiterr "Unknown public key algorithm ${KEY_ALGO}... can not continue."
  if [[ -n "${IP_VERSION}" ]]; then
    [[ "${IP_VERSION}" = "4" || "${IP_VERSION}" = "6" ]] || _exiterr "Unknown IP version ${IP_VERSION}... can not continue."
  fi
}

# Setup default config values, search for and load configuration files
load_config() {
  # Check for config in various locations
  if [[ -z "${CONFIG:-}" ]]; then
    for check_config in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${SCRIPTDIR}"; do
      if [[ -f "${check_config}/config" ]]; then
        BASEDIR="${check_config}"
        CONFIG="${check_config}/config"
        break
      fi
    done
  fi

  # Default values
  CA="https://acme-v01.api.letsencrypt.org/directory"
  LICENSE="https://letsencrypt.org/documents/LE-SA-v1.1.1-August-1-2016.pdf"
  CERTDIR=
  ACCOUNTDIR=
  CHALLENGETYPE="http-01"
  CONFIG_D=
  DOMAINS_D=
  DOMAINS_TXT=
  HOOK=
  HOOK_CHAIN="no"
  RENEW_DAYS="30"
  KEYSIZE="4096"
  WELLKNOWN=
  PRIVATE_KEY_RENEW="yes"
  KEY_ALGO=rsa
  OPENSSL_CNF="$(openssl version -d | cut -d\" -f2)/openssl.cnf"
  CONTACT_EMAIL=
  LOCKFILE=
  OCSP_MUST_STAPLE="no"
  IP_VERSION=

  if [[ -z "${CONFIG:-}" ]]; then
    echo "#" >&2
    echo "# !! WARNING !! No main config file found, using default config!" >&2
    echo "#" >&2
  elif [[ -f "${CONFIG}" ]]; then
    echo "# INFO: Using main config file ${CONFIG}"
    BASEDIR="$(dirname "${CONFIG}")"
    # shellcheck disable=SC1090
    . "${CONFIG}"
  else
    _exiterr "Specified config file doesn't exist."
  fi

  if [[ -n "${CONFIG_D}" ]]; then
    if [[ ! -d "${CONFIG_D}" ]]; then
      _exiterr "The path ${CONFIG_D} specified for CONFIG_D does not point to a directory." >&2
    fi

    for check_config_d in "${CONFIG_D}"/*.sh; do
      if [[ ! -e "${check_config_d}" ]]; then
        echo "# !! WARNING !! Extra configuration directory ${CONFIG_D} exists, but no configuration found in it." >&2
        break
      elif [[ -f "${check_config_d}" ]] && [[ -r "${check_config_d}" ]]; then
        echo "# INFO: Using additional config file ${check_config_d}"
        # shellcheck disable=SC1090
        . "${check_config_d}"
      else
        _exiterr "Specified additional config ${check_config_d} is not readable or not a file at all." >&2
      fi
   done
  fi

  # Remove slash from end of BASEDIR. Mostly for cleaner outputs, doesn't change functionality.
  BASEDIR="${BASEDIR%%/}"

  # Check BASEDIR and set default variables
  [[ -d "${BASEDIR}" ]] || _exiterr "BASEDIR does not exist: ${BASEDIR}"

  CAHASH="$(echo "${CA}" | urlbase64)"
  [[ -z "${ACCOUNTDIR}" ]] && ACCOUNTDIR="${BASEDIR}/accounts"
  mkdir -p "${ACCOUNTDIR}/${CAHASH}"
  [[ -f "${ACCOUNTDIR}/${CAHASH}/config" ]] && . "${ACCOUNTDIR}/${CAHASH}/config"
  ACCOUNT_KEY="${ACCOUNTDIR}/${CAHASH}/account_key.pem"
  ACCOUNT_KEY_JSON="${ACCOUNTDIR}/${CAHASH}/registration_info.json"

  if [[ -f "${BASEDIR}/private_key.pem" ]] && [[ ! -f "${ACCOUNT_KEY}" ]]; then
    echo "! Moving private_key.pem to ${ACCOUNT_KEY}"
    mv "${BASEDIR}/private_key.pem" "${ACCOUNT_KEY}"
  fi
  if [[ -f "${BASEDIR}/private_key.json" ]] && [[ ! -f "${ACCOUNT_KEY_JSON}" ]]; then
    echo "! Moving private_key.json to ${ACCOUNT_KEY_JSON}"
    mv "${BASEDIR}/private_key.json" "${ACCOUNT_KEY_JSON}"
  fi

  [[ -z "${CERTDIR}" ]] && CERTDIR="${BASEDIR}/certs"
  [[ -z "${DOMAINS_TXT}" ]] && DOMAINS_TXT="${BASEDIR}/domains.txt"
  [[ -z "${WELLKNOWN}" ]] && WELLKNOWN="/var/www/letsencrypt"
  [[ -z "${LOCKFILE}" ]] && LOCKFILE="${BASEDIR}/lock"
  [[ -n "${PARAM_NO_LOCK:-}" ]] && LOCKFILE=""

  [[ -n "${PARAM_HOOK:-}" ]] && HOOK="${PARAM_HOOK}"
  [[ -n "${PARAM_CERTDIR:-}" ]] && CERTDIR="${PARAM_CERTDIR}"
  [[ -n "${PARAM_CHALLENGETYPE:-}" ]] && CHALLENGETYPE="${PARAM_CHALLENGETYPE}"
  [[ -n "${PARAM_KEY_ALGO:-}" ]] && KEY_ALGO="${PARAM_KEY_ALGO}"
  [[ -n "${PARAM_OCSP_MUST_STAPLE:-}" ]] && OCSP_MUST_STAPLE="${PARAM_OCSP_MUST_STAPLE}"
  [[ -n "${PARAM_IP_VERSION:-}" ]] && IP_VERSION="${PARAM_IP_VERSION}"

  verify_config
  store_configvars
}

# Initialize system
init_system() {
  load_config

  # Lockfile handling (prevents concurrent access)
  if [[ -n "${LOCKFILE}" ]]; then
    LOCKDIR="$(dirname "${LOCKFILE}")"
    [[ -w "${LOCKDIR}" ]] || _exiterr "Directory ${LOCKDIR} for LOCKFILE ${LOCKFILE} is not writable, aborting."
    ( set -C; date > "${LOCKFILE}" ) 2>/dev/null || _exiterr "Lock file '${LOCKFILE}' present, aborting."
    remove_lock() { rm -f "${LOCKFILE}"; }
    trap 'remove_lock' EXIT
  fi

  # Get CA URLs
  CA_DIRECTORY="$(http_request get "${CA}")"
  CA_NEW_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-cert)" &&
  CA_NEW_AUTHZ="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-authz)" &&
  CA_NEW_REG="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-reg)" &&
  # shellcheck disable=SC2015
  CA_REVOKE_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value revoke-cert)" ||
  _exiterr "Problem retrieving ACME/CA-URLs, check if your configured CA points to the directory entrypoint."

  # Export some environment variables to be used in hook script
  export WELLKNOWN BASEDIR CERTDIR CONFIG

  # Checking for private key ...
  register_new_key="no"
  if [[ -n "${PARAM_ACCOUNT_KEY:-}" ]]; then
    # a private key was specified from the command line so use it for this run
    echo "Using private key ${PARAM_ACCOUNT_KEY} instead of account key"
    ACCOUNT_KEY="${PARAM_ACCOUNT_KEY}"
    ACCOUNT_KEY_JSON="${PARAM_ACCOUNT_KEY}.json"
  else
    # Check if private account key exists, if it doesn't exist yet generate a new one (rsa key)
    if [[ ! -e "${ACCOUNT_KEY}" ]]; then
      echo "+ Generating account key..."
      _openssl genrsa -out "${ACCOUNT_KEY}" "${KEYSIZE}"
      register_new_key="yes"
    fi
  fi
  openssl rsa -in "${ACCOUNT_KEY}" -check 2>/dev/null > /dev/null || _exiterr "Account key is not valid, can not continue."

  # Get public components from private key and calculate thumbprint
  pubExponent64="$(printf '%x' "$(openssl rsa -in "${ACCOUNT_KEY}" -noout -text | awk '/publicExponent/ {print $2}')" | hex2bin | urlbase64)"
  pubMod64="$(openssl rsa -in "${ACCOUNT_KEY}" -noout -modulus | cut -d'=' -f2 | hex2bin | urlbase64)"

  thumbprint="$(printf '{"e":"%s","kty":"RSA","n":"%s"}' "${pubExponent64}" "${pubMod64}" | openssl dgst -sha256 -binary | urlbase64)"

  # If we generated a new private key in the step above we have to register it with the acme-server
  if [[ "${register_new_key}" = "yes" ]]; then
    echo "+ Registering account key with letsencrypt..."
    [[ ! -z "${CA_NEW_REG}" ]] || _exiterr "Certificate authority doesn't allow registrations."
    # If an email for the contact has been provided then adding it to the registration request
    FAILED=false
    if [[ -n "${CONTACT_EMAIL}" ]]; then
      (signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "contact":["mailto:'"${CONTACT_EMAIL}"'"], "agreement": "'"$LICENSE"'"}' > "${ACCOUNT_KEY_JSON}") || FAILED=true
    else
      (signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "agreement": "'"$LICENSE"'"}' > "${ACCOUNT_KEY_JSON}") || FAILED=true
    fi
    if [[ "${FAILED}" = "true" ]]; then
      echo
      echo
      echo "Error registering account key. See message above for more information."
      rm "${ACCOUNT_KEY}" "${ACCOUNT_KEY_JSON}"
      exit 1
    fi
  fi

}

# Different sed version for different os types...
_sed() {
  if [[ "${OSTYPE}" = "Linux" ]]; then
    sed -r "${@}"
  else
    sed -E "${@}"
  fi
}

# Print error message and exit with error
_exiterr() {
  echo "ERROR: ${1}" >&2
  exit 1
}

# Remove newlines and whitespace from json
clean_json() {
  tr -d '\r\n' | _sed -e 's/ +/ /g' -e 's/\{ /{/g' -e 's/ \}/}/g' -e 's/\[ /[/g' -e 's/ \]/]/g'
}

# Encode data as url-safe formatted base64
urlbase64() {
  # urlbase64: base64 encoded string with '+' replaced with '-' and '/' replaced with '_'
  openssl base64 -e | tr -d '\n\r' | _sed -e 's:=*$::g' -e 'y:+/:-_:'
}

# Convert hex string to binary data
hex2bin() {
  # Remove spaces, add leading zero, escape as hex string and parse with printf
  printf -- "$(cat | _sed -e 's/[[:space:]]//g' -e 's/^(.(.{2})*)$/0\1/' -e 's/(.{2})/\\x\1/g')"
}

# Get string value from json dictionary
get_json_string_value() {
  local filter
  filter=$(printf 's/.*"%s": *"\([^"]*\)".*/\\1/p' "$1")
  sed -n "${filter}"
}

# OpenSSL writes to stderr/stdout even when there are no errors. So just
# display the output if the exit code was != 0 to simplify debugging.
_openssl() {
  set +e
  out="$(openssl "${@}" 2>&1)"
  res=$?
  set -e
  if [[ ${res} -ne 0 ]]; then
    echo "  + ERROR: failed to run $* (Exitcode: ${res})" >&2
    echo >&2
    echo "Details:" >&2
    echo "${out}" >&2
    echo >&2
    exit ${res}
  fi
}

# Send http(s) request with specified method
http_request() {
  tempcont="$(_mktemp)"

  if [[ -n "${IP_VERSION:-}" ]]; then
      ip_version="-${IP_VERSION}"
  fi

  set +e
  if [[ "${1}" = "head" ]]; then
    statuscode="$(curl ${ip_version:-} -s -w "%{http_code}" -o "${tempcont}" "${2}" -I)"
    curlret="${?}"
  elif [[ "${1}" = "get" ]]; then
    statuscode="$(curl ${ip_version:-} -s -w "%{http_code}" -o "${tempcont}" "${2}")"
    curlret="${?}"
  elif [[ "${1}" = "post" ]]; then
    statuscode="$(curl ${ip_version:-} -s -w "%{http_code}" -o "${tempcont}" "${2}" -d "${3}")"
    curlret="${?}"
  else
    set -e
    _exiterr "Unknown request method: ${1}"
  fi
  set -e

  if [[ ! "${curlret}" = "0" ]]; then
    _exiterr "Problem connecting to server (${1} for ${2}; curl returned with ${curlret})"
  fi

  if [[ ! "${statuscode:0:1}" = "2" ]]; then
    echo "  + ERROR: An error occurred while sending ${1}-request to ${2} (Status ${statuscode})" >&2
    echo >&2
    echo "Details:" >&2
    cat "${tempcont}" >&2
    echo >&2
    echo >&2
    rm -f "${tempcont}"

    # Wait for hook script to clean the challenge if used
    if [[ -n "${HOOK}" ]] && [[ "${HOOK_CHAIN}" != "yes" ]] && [[ -n "${challenge_token:+set}" ]]; then
      "${HOOK}" "clean_challenge" '' "${challenge_token}" "${keyauth}"
    fi

    # remove temporary domains.txt file if used
    [[ -n "${PARAM_DOMAIN:-}" && -n "${DOMAINS_TXT:-}" ]] && rm "${DOMAINS_TXT}"
    exit 1
  fi

  cat "${tempcont}"
  rm -f "${tempcont}"
}

# Send signed request
signed_request() {
  # Encode payload as urlbase64
  payload64="$(printf '%s' "${2}" | urlbase64)"

  # Retrieve nonce from acme-server
  nonce="$(http_request head "${CA}" | grep Replay-Nonce: | awk -F ': ' '{print $2}' | tr -d '\n\r')"

  # Build header with just our public key and algorithm information
  header='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}}'

  # Build another header which also contains the previously received nonce and encode it as urlbase64
  protected='{"alg": "RS256", "jwk": {"e": "'"${pubExponent64}"'", "kty": "RSA", "n": "'"${pubMod64}"'"}, "nonce": "'"${nonce}"'"}'
  protected64="$(printf '%s' "${protected}" | urlbase64)"

  # Sign header with nonce and our payload with our private key and encode signature as urlbase64
  signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign "${ACCOUNT_KEY}" | urlbase64)"

  # Send header + extended header + payload + signature to the acme-server
  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  http_request post "${1}" "${data}"
}

# Extracts all subject names from a CSR
# Outputs either the CN, or the SANs, one per line
extract_altnames() {
  csr="${1}" # the CSR itself (not a file)

  if ! <<<"${csr}" openssl req -verify -noout 2>/dev/null; then
    _exiterr "Certificate signing request isn't valid"
  fi

  reqtext="$( <<<"${csr}" openssl req -noout -text )"
  if <<<"${reqtext}" grep -q '^[[:space:]]*X509v3 Subject Alternative Name:[[:space:]]*$'; then
    # SANs used, extract these
    altnames="$( <<<"${reqtext}" grep -A1 '^[[:space:]]*X509v3 Subject Alternative Name:[[:space:]]*$' | tail -n1 )"
    # split to one per line:
    # shellcheck disable=SC1003
    altnames="$( <<<"${altnames}" _sed -e 's/^[[:space:]]*//; s/, /\'$'\n''/g' )"
    # we can only get DNS: ones signed
    if grep -qv '^DNS:' <<<"${altnames}"; then
      _exiterr "Certificate signing request contains non-DNS Subject Alternative Names"
    fi
    # strip away the DNS: prefix
    altnames="$( <<<"${altnames}" _sed -e 's/^DNS://' )"
    echo "${altnames}"

  else
    # No SANs, extract CN
    altnames="$( <<<"${reqtext}" grep '^[[:space:]]*Subject:' | _sed -e 's/.* CN=([^ /,]*).*/\1/' )"
    echo "${altnames}"
  fi
}

# Create certificate for domain(s) and outputs it FD 3
sign_csr() {
  csr="${1}" # the CSR itself (not a file)

  if { true >&3; } 2>/dev/null; then
    : # fd 3 looks OK
  else
    _exiterr "sign_csr: FD 3 not open"
  fi

  shift 1 || true
  altnames="${*:-}"
  if [ -z "${altnames}" ]; then
    altnames="$( extract_altnames "${csr}" )"
  fi

  if [[ -z "${CA_NEW_AUTHZ}" ]] || [[ -z "${CA_NEW_CERT}" ]]; then
    _exiterr "Certificate authority doesn't allow certificate signing"
  fi

  local idx=0
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    local -A challenge_uris challenge_tokens keyauths deploy_args
  else
    local -a challenge_uris challenge_tokens keyauths deploy_args
  fi

  # Request challenges
  for altname in ${altnames}; do
    # Ask the acme-server for new challenge token and extract them from the resulting json block
    echo " + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA_NEW_AUTHZ}" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}' | clean_json)"

    challenges="$(printf '%s\n' "${response}" | sed -n 's/.*\("challenges":[^\[]*\[[^]]*]\).*/\1/p')"
    repl=$'\n''{' # fix syntax highlighting in Vim
    challenge="$(printf "%s" "${challenges//\{/${repl}}" | grep \""${CHALLENGETYPE}"\")"
    challenge_token="$(printf '%s' "${challenge}" | get_json_string_value token | _sed 's/[^A-Za-z0-9_\-]/_/g')"
    challenge_uri="$(printf '%s' "${challenge}" | get_json_string_value uri)"

    if [[ -z "${challenge_token}" ]] || [[ -z "${challenge_uri}" ]]; then
      _exiterr "Can't retrieve challenges (${response})"
    fi

    # Challenge response consists of the challenge token and the thumbprint of our public certificate
    keyauth="${challenge_token}.${thumbprint}"

    case "${CHALLENGETYPE}" in
      "http-01")
        # Store challenge response in well-known location and make world-readable (so that a webserver can access it)
        printf '%s' "${keyauth}" > "${WELLKNOWN}/${challenge_token}"
        chmod a+r "${WELLKNOWN}/${challenge_token}"
        keyauth_hook="${keyauth}"
        ;;
      "dns-01")
        # Generate DNS entry content for dns-01 validation
        keyauth_hook="$(printf '%s' "${keyauth}" | openssl dgst -sha256 -binary | urlbase64)"
        ;;
    esac

    challenge_uris[${idx}]="${challenge_uri}"
    keyauths[${idx}]="${keyauth}"
    challenge_tokens[${idx}]="${challenge_token}"
    # Note: assumes args will never have spaces!
    deploy_args[${idx}]="${altname} ${challenge_token} ${keyauth_hook}"
    idx=$((idx+1))
  done

  # Wait for hook script to deploy the challenges if used
  # shellcheck disable=SC2068
  [[ -n "${HOOK}" ]] && [[ "${HOOK_CHAIN}" = "yes" ]] && "${HOOK}" "deploy_challenge" ${deploy_args[@]}

  # Respond to challenges
  idx=0
  for altname in ${altnames}; do
    challenge_token="${challenge_tokens[${idx}]}"
    keyauth="${keyauths[${idx}]}"

    # Wait for hook script to deploy the challenge if used
    # shellcheck disable=SC2086
    [[ -n "${HOOK}" ]] && [[ "${HOOK_CHAIN}" != "yes" ]] && "${HOOK}" "deploy_challenge" ${deploy_args[${idx}]}

    # Ask the acme-server to verify our challenge and wait until it is no longer pending
    echo " + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uris[${idx}]}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}' | clean_json)"

    reqstatus="$(printf '%s\n' "${result}" | get_json_string_value status)"

    while [[ "${reqstatus}" = "pending" ]]; do
      sleep 1
      result="$(http_request get "${challenge_uris[${idx}]}")"
      reqstatus="$(printf '%s\n' "${result}" | get_json_string_value status)"
    done

    [[ "${CHALLENGETYPE}" = "http-01" ]] && rm -f "${WELLKNOWN}/${challenge_token}"

    # Wait for hook script to clean the challenge if used
    if [[ -n "${HOOK}" ]] && [[ "${HOOK_CHAIN}" != "yes" ]] && [[ -n "${challenge_token}" ]]; then
      # shellcheck disable=SC2086
      "${HOOK}" "clean_challenge" ${deploy_args[${idx}]}
    fi
    idx=$((idx+1))

    if [[ "${reqstatus}" = "valid" ]]; then
      echo " + Challenge is valid!"
    else
      break
    fi
  done

  # Wait for hook script to clean the challenges if used
  # shellcheck disable=SC2068
  [[ -n "${HOOK}" ]] && [[ "${HOOK_CHAIN}" = "yes" ]] && "${HOOK}" "clean_challenge" ${deploy_args[@]}

  if [[ "${reqstatus}" != "valid" ]]; then
    # Clean up any remaining challenge_tokens if we stopped early
    if [[ "${CHALLENGETYPE}" = "http-01" ]]; then
      while [ ${idx} -lt ${#challenge_tokens[@]} ]; do
        rm -f "${WELLKNOWN}/${challenge_tokens[${idx}]}"
        idx=$((idx+1))
      done
    fi

    _exiterr "Challenge is invalid! (returned: ${reqstatus}) (result: ${result})"
  fi

  # Finally request certificate from the acme-server and store it in cert-${timestamp}.pem and link from cert.pem
  echo " + Requesting certificate..."
  csr64="$( <<<"${csr}" openssl req -outform DER | urlbase64)"
  crt64="$(signed_request "${CA_NEW_CERT}" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | openssl base64 -e)"
  crt="$( printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "${crt64}" )"

  # Try to load the certificate to detect corruption
  echo " + Checking certificate..."
  _openssl x509 -text <<<"${crt}"

  echo "${crt}" >&3

  unset challenge_token
  echo " + Done!"
}

# Create certificate for domain(s)
sign_domain() {
  domain="${1}"
  altnames="${*}"
  timestamp="$(date +%s)"

  echo " + Signing domains..."
  if [[ -z "${CA_NEW_AUTHZ}" ]] || [[ -z "${CA_NEW_CERT}" ]]; then
    _exiterr "Certificate authority doesn't allow certificate signing"
  fi

  # If there is no existing certificate directory => make it
  if [[ ! -e "${CERTDIR}/${domain}" ]]; then
    echo " + Creating new directory ${CERTDIR}/${domain} ..."
    mkdir -p "${CERTDIR}/${domain}" || _exiterr "Unable to create directory ${CERTDIR}/${domain}"
  fi

  privkey="privkey.pem"
  # generate a new private key if we need or want one
  if [[ ! -r "${CERTDIR}/${domain}/privkey.pem" ]] || [[ "${PRIVATE_KEY_RENEW}" = "yes" ]]; then
    echo " + Generating private key..."
    privkey="privkey-${timestamp}.pem"
    case "${KEY_ALGO}" in
      rsa) _openssl genrsa -out "${CERTDIR}/${domain}/privkey-${timestamp}.pem" "${KEYSIZE}";;
      prime256v1|secp384r1) _openssl ecparam -genkey -name "${KEY_ALGO}" -out "${CERTDIR}/${domain}/privkey-${timestamp}.pem";;
    esac
  fi

  # Generate signing request config and the actual signing request
  echo " + Generating signing request..."
  SAN=""
  for altname in ${altnames}; do
    SAN+="DNS:${altname}, "
  done
  SAN="${SAN%%, }"
  local tmp_openssl_cnf
  tmp_openssl_cnf="$(_mktemp)"
  cat "${OPENSSL_CNF}" > "${tmp_openssl_cnf}"
  printf "[SAN]\nsubjectAltName=%s" "${SAN}" >> "${tmp_openssl_cnf}"
  if [ "${OCSP_MUST_STAPLE}" = "yes" ]; then
    printf "\n1.3.6.1.5.5.7.1.24=DER:30:03:02:01:05" >> "${tmp_openssl_cnf}"
  fi
  openssl req -new -sha256 -key "${CERTDIR}/${domain}/${privkey}" -out "${CERTDIR}/${domain}/cert-${timestamp}.csr" -subj "/CN=${domain}/" -reqexts SAN -config "${tmp_openssl_cnf}"
  rm -f "${tmp_openssl_cnf}"

  crt_path="${CERTDIR}/${domain}/cert-${timestamp}.pem"
  # shellcheck disable=SC2086
  sign_csr "$(< "${CERTDIR}/${domain}/cert-${timestamp}.csr" )" ${altnames} 3>"${crt_path}"

  # Create fullchain.pem
  echo " + Creating fullchain.pem..."
  cat "${crt_path}" > "${CERTDIR}/${domain}/fullchain-${timestamp}.pem"
  http_request get "$(openssl x509 -in "${CERTDIR}/${domain}/cert-${timestamp}.pem" -noout -text | grep 'CA Issuers - URI:' | cut -d':' -f2-)" > "${CERTDIR}/${domain}/chain-${timestamp}.pem"
  if ! grep -q "BEGIN CERTIFICATE" "${CERTDIR}/${domain}/chain-${timestamp}.pem"; then
    openssl x509 -in "${CERTDIR}/${domain}/chain-${timestamp}.pem" -inform DER -out "${CERTDIR}/${domain}/chain-${timestamp}.pem" -outform PEM
  fi
  cat "${CERTDIR}/${domain}/chain-${timestamp}.pem" >> "${CERTDIR}/${domain}/fullchain-${timestamp}.pem"

  # Update symlinks
  [[ "${privkey}" = "privkey.pem" ]] || ln -sf "privkey-${timestamp}.pem" "${CERTDIR}/${domain}/privkey.pem"

  ln -sf "chain-${timestamp}.pem" "${CERTDIR}/${domain}/chain.pem"
  ln -sf "fullchain-${timestamp}.pem" "${CERTDIR}/${domain}/fullchain.pem"
  ln -sf "cert-${timestamp}.csr" "${CERTDIR}/${domain}/cert.csr"
  ln -sf "cert-${timestamp}.pem" "${CERTDIR}/${domain}/cert.pem"

  # Wait for hook script to clean the challenge and to deploy cert if used
  export KEY_ALGO
  [[ -n "${HOOK}" ]] && "${HOOK}" "deploy_cert" "${domain}" "${CERTDIR}/${domain}/privkey.pem" "${CERTDIR}/${domain}/cert.pem" "${CERTDIR}/${domain}/fullchain.pem" "${CERTDIR}/${domain}/chain.pem" "${timestamp}"

  unset challenge_token
  echo " + Done!"
}

# Usage: --cron (-c)
# Description: Sign/renew non-existant/changed/expiring certificates.
command_sign_domains() {
  init_system

  if [[ -n "${PARAM_DOMAIN:-}" ]]; then
    DOMAINS_TXT="$(_mktemp)"
    printf -- "${PARAM_DOMAIN}" > "${DOMAINS_TXT}"
  elif [[ -e "${DOMAINS_TXT}" ]]; then
    if [[ ! -r "${DOMAINS_TXT}" ]]; then
      _exiterr "domains.txt found but not readable"
    fi
  else
    _exiterr "domains.txt not found and --domain not given"
  fi

  # Generate certificates for all domains found in domains.txt. Check if existing certificate are about to expire
  ORIGIFS="${IFS}"
  IFS=$'\n'
  for line in $(<"${DOMAINS_TXT}" tr -d '\r' | tr '[:upper:]' '[:lower:]' | _sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e 's/[[:space:]]+/ /g' | (grep -vE '^(#|$)' || true)); do
    reset_configvars
    IFS="${ORIGIFS}"
    domain="$(printf '%s\n' "${line}" | cut -d' ' -f1)"
    morenames="$(printf '%s\n' "${line}" | cut -s -d' ' -f2-)"
    cert="${CERTDIR}/${domain}/cert.pem"

    force_renew="${PARAM_FORCE:-no}"

    if [[ -z "${morenames}" ]];then
      echo "Processing ${domain}"
    else
      echo "Processing ${domain} with alternative names: ${morenames}"
    fi

    # read cert config
    # for now this loads the certificate specific config in a subshell and parses a diff of set variables.
    # we could just source the config file but i decided to go this way to protect people from accidentally overriding
    # variables used internally by this script itself.
    if [[ -n "${DOMAINS_D}" ]]; then
      certconfig="${DOMAINS_D}/${domain}"
    else
      certconfig="${CERTDIR}/${domain}/config"
    fi

    if [ -f "${certconfig}" ]; then
      echo " + Using certificate specific config file!"
      ORIGIFS="${IFS}"
      IFS=$'\n'
      for cfgline in $(
        beforevars="$(_mktemp)"
        aftervars="$(_mktemp)"
        set > "${beforevars}"
        # shellcheck disable=SC1090
        . "${certconfig}"
        set > "${aftervars}"
        diff -u "${beforevars}" "${aftervars}" | grep -E '^\+[^+]'
        rm "${beforevars}"
        rm "${aftervars}"
      ); do
        config_var="$(echo "${cfgline:1}" | cut -d'=' -f1)"
        config_value="$(echo "${cfgline:1}" | cut -d'=' -f2-)"
        case "${config_var}" in
          KEY_ALGO|OCSP_MUST_STAPLE|PRIVATE_KEY_RENEW|KEYSIZE|CHALLENGETYPE|HOOK|WELLKNOWN|HOOK_CHAIN|OPENSSL_CNF|RENEW_DAYS)
            echo "   + ${config_var} = ${config_value}"
            declare -- "${config_var}=${config_value}"
            ;;
          _) ;;
          *) echo "   ! Setting ${config_var} on a per-certificate base is not (yet) supported"
        esac
      done
      IFS="${ORIGIFS}"
    fi
    verify_config

    if [[ -e "${cert}" ]]; then
      printf " + Checking domain name(s) of existing cert..."

      certnames="$(openssl x509 -in "${cert}" -text -noout | grep DNS: | _sed 's/DNS://g' | tr -d ' ' | tr ',' '\n' | sort -u | tr '\n' ' ' | _sed 's/ $//')"
      givennames="$(echo "${domain}" "${morenames}"| tr ' ' '\n' | sort -u | tr '\n' ' ' | _sed 's/ $//' | _sed 's/^ //')"

      if [[ "${certnames}" = "${givennames}" ]]; then
        echo " unchanged."
      else
        echo " changed!"
        echo " + Domain name(s) are not matching!"
        echo " + Names in old certificate: ${certnames}"
        echo " + Configured names: ${givennames}"
        echo " + Forcing renew."
        force_renew="yes"
      fi
    fi

    if [[ -e "${cert}" ]]; then
      echo " + Checking expire date of existing cert..."
      valid="$(openssl x509 -enddate -noout -in "${cert}" | cut -d= -f2- )"

      printf " + Valid till %s " "${valid}"
      if openssl x509 -checkend $((RENEW_DAYS * 86400)) -noout -in "${cert}"; then
        printf "(Longer than %d days). " "${RENEW_DAYS}"
        if [[ "${force_renew}" = "yes" ]]; then
          echo "Ignoring because renew was forced!"
        else
          # Certificate-Names unchanged and cert is still valid
          echo "Skipping renew!"
          [[ -n "${HOOK}" ]] && "${HOOK}" "unchanged_cert" "${domain}" "${CERTDIR}/${domain}/privkey.pem" "${CERTDIR}/${domain}/cert.pem" "${CERTDIR}/${domain}/fullchain.pem" "${CERTDIR}/${domain}/chain.pem"
          continue
        fi
      else
        echo "(Less than ${RENEW_DAYS} days). Renewing!"
      fi
    fi

    # shellcheck disable=SC2086
    if [[ "${PARAM_KEEP_GOING:-}" = "yes" ]]; then
      sign_domain ${line} &
      wait $! || true
    else
      sign_domain ${line}
    fi
  done

  # remove temporary domains.txt file if used
  [[ -n "${PARAM_DOMAIN:-}" ]] && rm -f "${DOMAINS_TXT}"

  exit 0
}

# Usage: --signcsr (-s) path/to/csr.pem
# Description: Sign a given CSR, output CRT on stdout (advanced usage)
command_sign_csr() {
  # redirect stdout to stderr
  # leave stdout over at fd 3 to output the cert
  exec 3>&1 1>&2

  init_system

  csrfile="${1}"
  if [ ! -r "${csrfile}" ]; then
    _exiterr "Could not read certificate signing request ${csrfile}"
  fi

  # gen cert
  certfile="$(_mktemp)"
  sign_csr "$(< "${csrfile}" )" 3> "${certfile}"

  # print cert
  echo "# CERT #" >&3
  cat "${certfile}" >&3
  echo >&3

  # print chain
  if [ -n "${PARAM_FULL_CHAIN:-}" ]; then
    # get and convert ca cert
    chainfile="$(_mktemp)"
    http_request get "$(openssl x509 -in "${certfile}" -noout -text | grep 'CA Issuers - URI:' | cut -d':' -f2-)" > "${chainfile}"

    if ! grep -q "BEGIN CERTIFICATE" "${chainfile}"; then
      openssl x509 -inform DER -in "${chainfile}" -outform PEM -out "${chainfile}"
    fi

    echo "# CHAIN #" >&3
    cat "${chainfile}" >&3

    rm "${chainfile}"
  fi

  # cleanup
  rm "${certfile}"

  exit 0
}

# Usage: --revoke (-r) path/to/cert.pem
# Description: Revoke specified certificate
command_revoke() {
  init_system

  [[ -n "${CA_REVOKE_CERT}" ]] || _exiterr "Certificate authority doesn't allow certificate revocation."

  cert="${1}"
  if [[ -L "${cert}" ]]; then
    # follow symlink and use real certificate name (so we move the real file and not the symlink at the end)
    local link_target
    link_target="$(readlink -n "${cert}")"
    if [[ "${link_target}" =~ ^/ ]]; then
      cert="${link_target}"
    else
      cert="$(dirname "${cert}")/${link_target}"
    fi
  fi
  [[ -f "${cert}" ]] || _exiterr "Could not find certificate ${cert}"

  echo "Revoking ${cert}"

  cert64="$(openssl x509 -in "${cert}" -inform PEM -outform DER | urlbase64)"
  response="$(signed_request "${CA_REVOKE_CERT}" '{"resource": "revoke-cert", "certificate": "'"${cert64}"'"}' | clean_json)"
  # if there is a problem with our revoke request _request (via signed_request) will report this and "exit 1" out
  # so if we are here, it is safe to assume the request was successful
  echo " + Done."
  echo " + Renaming certificate to ${cert}-revoked"
  mv -f "${cert}" "${cert}-revoked"
}

# Usage: --cleanup (-gc)
# Description: Move unused certificate files to archive directory
command_cleanup() {
  load_config

  # Create global archive directory if not existant
  if [[ ! -e "${BASEDIR}/archive" ]]; then
    mkdir "${BASEDIR}/archive"
  fi

  # Loop over all certificate directories
  for certdir in "${CERTDIR}/"*; do
    # Skip if entry is not a folder
    [[ -d "${certdir}" ]] || continue

    # Get certificate name
    certname="$(basename "${certdir}")"

    # Create certitifaces archive directory if not existant
    archivedir="${BASEDIR}/archive/${certname}"
    if [[ ! -e "${archivedir}" ]]; then
      mkdir "${archivedir}"
    fi

    # Loop over file-types (certificates, keys, signing-requests, ...)
    for filetype in cert.csr cert.pem chain.pem fullchain.pem privkey.pem; do
      # Skip if symlink is broken
      [[ -r "${certdir}/${filetype}" ]] || continue

      # Look up current file in use
      current="$(basename "$(readlink "${certdir}/${filetype}")")"

      # Split filetype into name and extension
      filebase="$(echo "${filetype}" | cut -d. -f1)"
      fileext="$(echo "${filetype}" | cut -d. -f2)"

      # Loop over all files of this type
      for file in "${certdir}/${filebase}-"*".${fileext}"; do
        # Handle case where no files match the wildcard
        [[ -f "${file}" ]] || break

        # Check if current file is in use, if unused move to archive directory
        filename="$(basename "${file}")"
        if [[ ! "${filename}" = "${current}" ]]; then
          echo "Moving unused file to archive directory: ${certname}/${filename}"
          mv "${certdir}/${filename}" "${archivedir}/${filename}"
        fi
      done
    done
  done

  exit 0
}

# Usage: --help (-h)
# Description: Show help text
command_help() {
  printf "Usage: %s [-h] [command [argument]] [parameter [argument]] [parameter [argument]] ...\n\n" "${0}"
  printf "Default command: help\n\n"
  echo "Commands:"
  grep -e '^[[:space:]]*# Usage:' -e '^[[:space:]]*# Description:' -e '^command_.*()[[:space:]]*{' "${0}" | while read -r usage; read -r description; read -r command; do
    if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]] || [[ ! "${command}" =~ ^command_ ]]; then
      _exiterr "Error generating help text."
    fi
    printf " %-32s %s\n" "${usage##"# Usage: "}" "${description##"# Description: "}"
  done
  printf -- "\nParameters:\n"
  grep -E -e '^[[:space:]]*# PARAM_Usage:' -e '^[[:space:]]*# PARAM_Description:' "${0}" | while read -r usage; read -r description; do
    if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]]; then
      _exiterr "Error generating help text."
    fi
    printf " %-32s %s\n" "${usage##"# PARAM_Usage: "}" "${description##"# PARAM_Description: "}"
  done
}

# Usage: --env (-e)
# Description: Output configuration variables for use in other scripts
command_env() {
  echo "# letsencrypt.sh configuration"
  load_config
  typeset -p CA LICENSE CERTDIR CHALLENGETYPE DOMAINS_D DOMAINS_TXT HOOK HOOK_CHAIN RENEW_DAYS ACCOUNT_KEY ACCOUNT_KEY_JSON KEYSIZE WELLKNOWN PRIVATE_KEY_RENEW OPENSSL_CNF CONTACT_EMAIL LOCKFILE
}

# Main method (parses script arguments and calls command_* methods)
main() {
  COMMAND=""
  set_command() {
    [[ -z "${COMMAND}" ]] || _exiterr "Only one command can be executed at a time. See help (-h) for more information."
    COMMAND="${1}"
  }

  check_parameters() {
    if [[ -z "${1:-}" ]]; then
      echo "The specified command requires additional parameters. See help:" >&2
      echo >&2
      command_help >&2
      exit 1
    elif [[ "${1:0:1}" = "-" ]]; then
      _exiterr "Invalid argument: ${1}"
    fi
  }

  [[ -z "${@}" ]] && eval set -- "--help"

  while (( ${#} )); do
    case "${1}" in
      --help|-h)
        command_help
        exit 0
        ;;

      --env|-e)
        set_command env
        ;;

      --cron|-c)
        set_command sign_domains
        ;;

      --signcsr|-s)
        shift 1
        set_command sign_csr
        check_parameters "${1:-}"
        PARAM_CSR="${1}"
        ;;

      --revoke|-r)
        shift 1
        set_command revoke
        check_parameters "${1:-}"
        PARAM_REVOKECERT="${1}"
        ;;

      --cleanup|-gc)
        set_command cleanup
        ;;

      # PARAM_Usage: --full-chain (-fc)
      # PARAM_Description: Print full chain when using --signcsr
      --full-chain|-fc)
        PARAM_FULL_CHAIN="1"
        ;;

      # PARAM_Usage: --ipv4 (-4)
      # PARAM_Description: Resolve names to IPv4 addresses only
      --ipv4|-4)
        PARAM_IP_VERSION="4"
        ;;

      # PARAM_Usage: --ipv6 (-6)
      # PARAM_Description: Resolve names to IPv6 addresses only
      --ipv6|-6)
        PARAM_IP_VERSION="6"
        ;;

      # PARAM_Usage: --domain (-d) domain.tld
      # PARAM_Description: Use specified domain name(s) instead of domains.txt entry (one certificate!)
      --domain|-d)
        shift 1
        check_parameters "${1:-}"
        if [[ -z "${PARAM_DOMAIN:-}" ]]; then
          PARAM_DOMAIN="${1}"
        else
          PARAM_DOMAIN="${PARAM_DOMAIN} ${1}"
         fi
        ;;

      # PARAM_Usage: --keep-going (-g)
      # PARAM_Description: Keep going after encountering an error while creating/renewing multiple certificates in cron mode
      --keep-going|-g)
        PARAM_KEEP_GOING="yes"
        ;;

      # PARAM_Usage: --force (-x)
      # PARAM_Description: Force renew of certificate even if it is longer valid than value in RENEW_DAYS
      --force|-x)
        PARAM_FORCE="yes"
        ;;

      # PARAM_Usage: --no-lock (-n)
      # PARAM_Description: Don't use lockfile (potentially dangerous!)
      --no-lock|-n)
        PARAM_NO_LOCK="yes"
        ;;

      # PARAM_Usage: --ocsp
      # PARAM_Description: Sets option in CSR indicating OCSP stapling to be mandatory
      --ocsp)
        PARAM_OCSP_MUST_STAPLE="yes"
        ;;

      # PARAM_Usage: --privkey (-p) path/to/key.pem
      # PARAM_Description: Use specified private key instead of account key (useful for revocation)
      --privkey|-p)
        shift 1
        check_parameters "${1:-}"
        PARAM_ACCOUNT_KEY="${1}"
        ;;

      # PARAM_Usage: --config (-f) path/to/config
      # PARAM_Description: Use specified config file
      --config|-f)
        shift 1
        check_parameters "${1:-}"
        CONFIG="${1}"
        ;;

      # PARAM_Usage: --hook (-k) path/to/hook.sh
      # PARAM_Description: Use specified script for hooks
      --hook|-k)
        shift 1
        check_parameters "${1:-}"
        PARAM_HOOK="${1}"
        ;;

      # PARAM_Usage: --out (-o) certs/directory
      # PARAM_Description: Output certificates into the specified directory
      --out|-o)
        shift 1
        check_parameters "${1:-}"
        PARAM_CERTDIR="${1}"
        ;;

      # PARAM_Usage: --challenge (-t) http-01|dns-01
      # PARAM_Description: Which challenge should be used? Currently http-01 and dns-01 are supported
      --challenge|-t)
        shift 1
        check_parameters "${1:-}"
        PARAM_CHALLENGETYPE="${1}"
        ;;

      # PARAM_Usage: --algo (-a) rsa|prime256v1|secp384r1
      # PARAM_Description: Which public key algorithm should be used? Supported: rsa, prime256v1 and secp384r1
      --algo|-a)
        shift 1
        check_parameters "${1:-}"
        PARAM_KEY_ALGO="${1}"
        ;;

      *)
        echo "Unknown parameter detected: ${1}" >&2
        echo >&2
        command_help >&2
        exit 1
        ;;
    esac

    shift 1
  done

  case "${COMMAND}" in
    env) command_env;;
    sign_domains) command_sign_domains;;
    sign_csr) command_sign_csr "${PARAM_CSR}";;
    revoke) command_revoke "${PARAM_REVOKECERT}";;
    cleanup) command_cleanup;;
    *) command_help; exit 1;;
  esac
}

# Determine OS type
OSTYPE="$(uname)"

# Check for missing dependencies
check_dependencies

# Run script
main "${@:-}"
