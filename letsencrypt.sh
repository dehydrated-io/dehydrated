#!/usr/bin/env bash
set -e
set -u
set -o pipefail
umask 077 # paranoid umask, we're creating private keys

# Get the directory in which this script is stored
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASEDIR="${SCRIPTDIR}"

# Check for script dependencies
check_dependencies() {
  curl -V > /dev/null 2>&1 || _exiterr "This script requires curl."
  openssl version > /dev/null 2>&1 || _exiterr "This script requres an openssl binary."
  sed "" < /dev/null > /dev/null 2>&1 || _exiterr "This script requres sed."
  grep -V > /dev/null 2>&1 || _exiterr "This script requres grep."
  mktemp -u -t XXXXXX > /dev/null 2>&1 || _exiterr "This script requires mktemp."
}

# Setup default config values, search for and load configuration files
load_config() {
  # Check for config in various locations
  if [[ -z "${CONFIG:-}" ]]; then
    for check_config in "/etc/letsencrypt.sh" "/usr/local/etc/letsencrypt.sh" "${PWD}" "${SCRIPTDIR}"; do
      if [[ -e "${check_config}/config.sh" ]]; then
        BASEDIR="${check_config}"
        CONFIG="${check_config}/config.sh"
        break
      fi
    done
  fi

  # Default values
  CA="https://acme-v01.api.letsencrypt.org/directory"
  LICENSE="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"
  CHALLENGETYPE="http-01"
  HOOK=
  RENEW_DAYS="30"
  PRIVATE_KEY="${BASEDIR}/private_key.pem"
  KEYSIZE="4096"
  WELLKNOWN="${BASEDIR}/.acme-challenges"
  PRIVATE_KEY_RENEW="no"
  OPENSSL_CNF="$(openssl version -d | cut -d'"' -f2)/openssl.cnf"
  CONTACT_EMAIL=
  LOCKFILE="${BASEDIR}/lock"

  if [[ -z "${CONFIG:-}" ]]; then
    echo "#" >&2
    echo "# !! WARNING !! No config file found, using default config!" >&2
    echo "#" >&2
  elif [[ -e "${CONFIG}" ]]; then
    echo "# INFO: Using config file ${CONFIG}"
    BASEDIR="$(dirname "${CONFIG}")"
    # shellcheck disable=SC1090
    . "${CONFIG}"
  else
    _exiterr "Specified config file doesn't exist."
  fi

  # Remove slash from end of BASEDIR. Mostly for cleaner outputs, doesn't change functionality.
  BASEDIR="${BASEDIR%%/}"

  # Check BASEDIR and set default variables
  [[ -d "${BASEDIR}" ]] || _exiterr "BASEDIR does not exist: ${BASEDIR}"

  [[ -n "${PARAM_HOOK:-}" ]] && HOOK="${PARAM_HOOK}"
  [[ -n "${PARAM_CHALLENGETYPE:-}" ]] && CHALLENGETYPE="${PARAM_CHALLENGETYPE}"

  [[ "${CHALLENGETYPE}" =~ (http-01|dns-01) ]] || _exiterr "Unknown challenge type ${CHALLENGETYPE}... can not continue."
  if [[ "${CHALLENGETYPE}" = "dns-01" ]] && [[ -z "${HOOK}" ]]; then
   _exiterr "Challenge type dns-01 needs a hook script for deployment... can not continue."
  fi
}

# Initialize system
init_system() {
  load_config

  # Lockfile handling (prevents concurrent access)
  ( set -C; date > "${LOCKFILE}" ) 2>/dev/null || _exiterr "Lock file '${LOCKFILE}' present, aborting."
  remove_lock() { rm -f "${LOCKFILE}"; }
  trap 'remove_lock' EXIT

  # Get CA URLs
  CA_DIRECTORY="$(http_request get "${CA}")"
  CA_NEW_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-cert)" &&
  CA_NEW_AUTHZ="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-authz)" &&
  CA_NEW_REG="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value new-reg)" &&
  # shellcheck disable=SC2015
  CA_REVOKE_CERT="$(printf "%s" "${CA_DIRECTORY}" | get_json_string_value revoke-cert)" ||
  _exiterr "Problem retrieving ACME/CA-URLs, check if your configured CA points to the directory entrypoint."

  # Export some environment variables to be used in hook script
  export WELLKNOWN BASEDIR CONFIG

  # Checking for private key ...
  register_new_key="no"
  if [[ -n "${PARAM_PRIVATE_KEY:-}" ]]; then
    # a private key was specified from the command line so use it for this run
    echo "Using private key ${PARAM_PRIVATE_KEY} instead of account key"
    PRIVATE_KEY="${PARAM_PRIVATE_KEY}"
  else
    # Check if private account key exists, if it doesn't exist yet generate a new one (rsa key)
    if [[ ! -e "${PRIVATE_KEY}" ]]; then
      echo "+ Generating account key..."
      _openssl genrsa -out "${PRIVATE_KEY}" "${KEYSIZE}"
      register_new_key="yes"
    fi
  fi
  openssl rsa -in "${PRIVATE_KEY}" -check 2>/dev/null > /dev/null || _exiterr "Private key is not valid, can not continue."

  # Get public components from private key and calculate thumbprint
  pubExponent64="$(openssl rsa -in "${PRIVATE_KEY}" -noout -text | grep publicExponent | grep -oE "0x[a-f0-9]+" | cut -d'x' -f2 | hex2bin | urlbase64)"
  pubMod64="$(openssl rsa -in "${PRIVATE_KEY}" -noout -modulus | cut -d'=' -f2 | hex2bin | urlbase64)"

  thumbprint="$(printf '{"e":"%s","kty":"RSA","n":"%s"}' "${pubExponent64}" "${pubMod64}" | openssl sha -sha256 -binary | urlbase64)"

  # If we generated a new private key in the step above we have to register it with the acme-server
  if [[ "${register_new_key}" = "yes" ]]; then
    echo "+ Registering account key with letsencrypt..."
    [[ ! -z "${CA_NEW_REG}" ]] || _exiterr "Certificate authority doesn't allow registrations."
    # If an email for the contact has been provided then adding it to the registration request
    if [[ -n "${CONTACT_EMAIL}" ]]; then
      signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "contact":["mailto:'"${CONTACT_EMAIL}"'"], "agreement": "'"$LICENSE"'"}' > /dev/null
    else
      signed_request "${CA_NEW_REG}" '{"resource": "new-reg", "agreement": "'"$LICENSE"'"}' > /dev/null
    fi
  fi

  [[ -d "${WELLKNOWN}" ]] || _exiterr "WELLKNOWN directory doesn't exist, please create ${WELLKNOWN} and set appropriate permissions."
}

# Print error message and exit with error
_exiterr() {
  echo "ERROR: ${1}" >&2
  exit 1
}

# Encode data as url-safe formatted base64
urlbase64() {
  # urlbase64: base64 encoded string with '+' replaced with '-' and '/' replaced with '_'
  openssl base64 -e | tr -d '\n\r' | sed -e 's:=*$::g' -e 'y:+/:-_:'
}

# Convert hex string to binary data
hex2bin() {
  # Remove spaces, add leading zero, escape as hex string and parse with printf
  printf -- "$(cat | sed -E -e 's/[[:space:]]//g' -e 's/^(.(.{2})*)$/0\1/' -e 's/(.{2})/\\x\1/g')"
}

# Get string value from json dictionary
get_json_string_value() {
  grep -Eo '"'"${1}"'":[[:space:]]*"[^"]*"' | cut -d'"' -f4
}

# OpenSSL writes to stderr/stdout even when there are no errors. So just
# display the output if the exit code was != 0 to simplify debugging.
_openssl() {
  set +e
  out="$(openssl "${@}" 2>&1)"
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

# Send http(s) request with specified method
http_request() {
  tempcont="$(mktemp -t XXXXXX)"

  if [[ "${1}" = "head" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -I)"
  elif [[ "${1}" = "get" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}")"
  elif [[ "${1}" = "post" ]]; then
    statuscode="$(curl -s -w "%{http_code}" -o "${tempcont}" "${2}" -d "${3}")"
  else
    _exiterr "Unknown request method: ${1}"
  fi

  if [[ ! "${statuscode:0:1}" = "2" ]]; then
    echo "  + ERROR: An error occurred while sending ${1}-request to ${2} (Status ${statuscode})" >&2
    echo >&2
    echo "Details:" >&2
    cat "${tempcont}" >&2
    rm -f "${tempcont}"

    # Wait for hook script to clean the challenge if used
    if [[ -n "${HOOK}" ]] && [[ -n "${challenge_token:+set}" ]]; then
      ${HOOK} "clean_challenge" '' "${challenge_token}" "${keyauth}"
    fi

    # remove temporary domains.txt file if used
    [[ -n "${PARAM_DOMAIN:-}" ]] && rm "${DOMAINS_TXT}"
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
  signed64="$(printf '%s' "${protected64}.${payload64}" | openssl dgst -sha256 -sign "${PRIVATE_KEY}" | urlbase64)"

  # Send header + extended header + payload + signature to the acme-server
  data='{"header": '"${header}"', "protected": "'"${protected64}"'", "payload": "'"${payload64}"'", "signature": "'"${signed64}"'"}'

  http_request post "${1}" "${data}"
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
  if [[ ! -e "${BASEDIR}/certs/${domain}" ]]; then
    echo " + Creating new directory ${BASEDIR}/certs/${domain} ..."
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
  echo " + Generating signing request..."
  SAN=""
  for altname in ${altnames}; do
    SAN+="DNS:${altname}, "
  done
  SAN="${SAN%%, }"
  local tmp_openssl_cnf
  tmp_openssl_cnf="$(mktemp -t XXXXXX)"
  cat "${OPENSSL_CNF}" > "${tmp_openssl_cnf}"
  printf "[SAN]\nsubjectAltName=%s" "${SAN}" >> "${tmp_openssl_cnf}"
  openssl req -new -sha256 -key "${BASEDIR}/certs/${domain}/${privkey}" -out "${BASEDIR}/certs/${domain}/cert-${timestamp}.csr" -subj "/CN=${domain}/" -reqexts SAN -config "${tmp_openssl_cnf}"
  rm -f "${tmp_openssl_cnf}"

  # Request and respond to challenges
  for altname in ${altnames}; do
    # Ask the acme-server for new challenge token and extract them from the resulting json block
    echo " + Requesting challenge for ${altname}..."
    response="$(signed_request "${CA_NEW_AUTHZ}" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"${altname}"'"}}')"

    challenges="$(printf '%s\n' "${response}" | grep -Eo '"challenges":[^\[]*\[[^]]*]')"
    repl=$'\n''{' # fix syntax highlighting in Vim
    challenge="$(printf "%s" "${challenges//\{/${repl}}" | grep \""${CHALLENGETYPE}"\")"
    challenge_token="$(printf '%s' "${challenge}" | get_json_string_value token | sed 's/[^A-Za-z0-9_\-]/_/g')"
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
        keyauth_hook="$(printf '%s' "${keyauth}" | openssl sha -sha256 -binary | urlbase64)"
        ;;
    esac

    # Wait for hook script to deploy the challenge if used
    [[ -n "${HOOK}" ]] && ${HOOK} "deploy_challenge" "${altname}" "${challenge_token}" "${keyauth_hook}"

    # Ask the acme-server to verify our challenge and wait until it is no longer pending
    echo " + Responding to challenge for ${altname}..."
    result="$(signed_request "${challenge_uri}" '{"resource": "challenge", "keyAuthorization": "'"${keyauth}"'"}')"

    status="$(printf '%s\n' "${result}" | get_json_string_value status)"

    while [[ "${status}" = "pending" ]]; do
      sleep 1
      status="$(http_request get "${challenge_uri}" | get_json_string_value status)"
    done

    [[ "${CHALLENGETYPE}" = "http-01" ]] && rm -f "${WELLKNOWN}/${challenge_token}"

    # Wait for hook script to clean the challenge if used
    if [[ -n "${HOOK}" ]] && [[ -n "${challenge_token}" ]]; then
      ${HOOK} "clean_challenge" "${altname}" "${challenge_token}" "${keyauth_hook}"
    fi

    if [[ "${status}" = "valid" ]]; then
      echo " + Challenge is valid!"
    else
      _exiterr "Challenge is invalid! (returned: ${status})"
    fi
  done

  # Finally request certificate from the acme-server and store it in cert-${timestamp}.pem and link from cert.pem
  echo " + Requesting certificate..."
  csr64="$(openssl req -in "${BASEDIR}/certs/${domain}/cert-${timestamp}.csr" -outform DER | urlbase64)"
  crt64="$(signed_request "${CA_NEW_CERT}" '{"resource": "new-cert", "csr": "'"${csr64}"'"}' | openssl base64 -e)"
  crt_path="${BASEDIR}/certs/${domain}/cert-${timestamp}.pem"
  printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "${crt64}" > "${crt_path}"

  # Try to load the certificate to detect corruption
  echo " + Checking certificate..."
  _openssl x509 -text < "${crt_path}"

  # Create fullchain.pem
  echo " + Creating fullchain.pem..."
  cat "${crt_path}" > "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"
  http_request get "$(openssl x509 -in "${BASEDIR}/certs/${domain}/cert-${timestamp}.pem" -noout -text | grep 'CA Issuers - URI:' | cut -d':' -f2-)" > "${BASEDIR}/certs/${domain}/chain-${timestamp}.pem"
  if ! grep -q "BEGIN CERTIFICATE" "${BASEDIR}/certs/${domain}/chain-${timestamp}.pem"; then
    openssl x509 -in "${BASEDIR}/certs/${domain}/chain-${timestamp}.pem" -inform DER -out "${BASEDIR}/certs/${domain}/chain-${timestamp}.pem" -outform PEM
  fi
  cat "${BASEDIR}/certs/${domain}/chain-${timestamp}.pem" >> "${BASEDIR}/certs/${domain}/fullchain-${timestamp}.pem"

  # Update symlinks
  [[ "${privkey}" = "privkey.pem" ]] || ln -sf "privkey-${timestamp}.pem" "${BASEDIR}/certs/${domain}/privkey.pem"

  ln -sf "chain-${timestamp}.pem" "${BASEDIR}/certs/${domain}/chain.pem"
  ln -sf "fullchain-${timestamp}.pem" "${BASEDIR}/certs/${domain}/fullchain.pem"
  ln -sf "cert-${timestamp}.csr" "${BASEDIR}/certs/${domain}/cert.csr"
  ln -sf "cert-${timestamp}.pem" "${BASEDIR}/certs/${domain}/cert.pem"

  # Wait for hook script to clean the challenge and to deploy cert if used
  [[ -n "${HOOK}" ]] && ${HOOK} "deploy_cert" "${domain}" "${BASEDIR}/certs/${domain}/privkey.pem" "${BASEDIR}/certs/${domain}/cert.pem" "${BASEDIR}/certs/${domain}/fullchain.pem"

  unset challenge_token
  echo " + Done!"
}

# Usage: --cron (-c)
# Description: Sign/renew non-existant/changed/expiring certificates.
command_sign_domains() {
  init_system

  if [[ -n "${PARAM_DOMAIN:-}" ]]; then
    DOMAINS_TXT="$(mktemp -t XXXXXX)"
    printf -- "${PARAM_DOMAIN}" > "${DOMAINS_TXT}"
  elif [[ -e "${BASEDIR}/domains.txt" ]]; then
    DOMAINS_TXT="${BASEDIR}/domains.txt"
  else
    _exiterr "domains.txt not found and --domain not given"
  fi

  # Generate certificates for all domains found in domains.txt. Check if existing certificate are about to expire
  <"${DOMAINS_TXT}" sed -E -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e 's/[[:space:]]+/ /g' | (grep -vE '^(#|$)' || true) | while read -r line; do
    domain="$(printf '%s\n' "${line}" | cut -d' ' -f1)"
    morenames="$(printf '%s\n' "${line}" | cut -s -d' ' -f2-)"
    cert="${BASEDIR}/certs/${domain}/cert.pem"

    force_renew="${PARAM_FORCE:-no}"

    if [[ -z "${morenames}" ]];then
      echo "Processing ${domain}"
    else
      echo "Processing ${domain} with alternative names: ${morenames}"
    fi

    if [[ -e "${cert}" ]]; then
      printf " + Checking domain name(s) of existing cert..."

      certnames="$(openssl x509 -in "${cert}" -text -noout | grep DNS: | sed 's/DNS://g' | tr -d ' ' | tr ',' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"
      givennames="$(echo "${domain}" "${morenames}"| tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//' | sed 's/^ //')"

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
          echo "Skipping!"
          continue
        fi
      else
        echo "(Less than ${RENEW_DAYS} days). Renewing!"
      fi
    fi

    # shellcheck disable=SC2086
    sign_domain ${line}
  done

  # remove temporary domains.txt file if used
  [[ -n "${PARAM_DOMAIN:-}" ]] && rm -f "${DOMAINS_TXT}"

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
  response="$(signed_request "${CA_REVOKE_CERT}" '{"resource": "revoke-cert", "certificate": "'"${cert64}"'"}')"
  # if there is a problem with our revoke request _request (via signed_request) will report this and "exit 1" out
  # so if we are here, it is safe to assume the request was successful
  echo " + Done."
  echo " + Renaming certificate to ${cert}-revoked"
  mv -f "${cert}" "${cert}-revoked"
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
  typeset -p CA LICENSE CHALLENGETYPE HOOK RENEW_DAYS PRIVATE_KEY KEYSIZE WELLKNOWN PRIVATE_KEY_RENEW OPENSSL_CNF CONTACT_EMAIL LOCKFILE
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

  while (( "${#}" )); do
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

      --revoke|-r)
        shift 1
        set_command revoke
        check_parameters "${1:-}"
        PARAM_REVOKECERT="${1}"
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


      # PARAM_Usage: --force (-x)
      # PARAM_Description: Force renew of certificate even if it is longer valid than value in RENEW_DAYS
      --force|-x)
        PARAM_FORCE="yes"
        ;;

      # PARAM_Usage: --privkey (-p) path/to/key.pem
      # PARAM_Description: Use specified private key instead of account key (useful for revocation)
      --privkey|-p)
        shift 1
        check_parameters "${1:-}"
        PARAM_PRIVATE_KEY="${1}"
        ;;

      # PARAM_Usage: --config (-f) path/to/config.sh
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

      # PARAM_Usage: --challenge (-t) http-01|dns-01
      # PARAM_Description: Which challenge should be used? Currently http-01 and dns-01 are supported
      --challenge|-t)
        shift 1
        check_parameters "${1:-}"
        PARAM_CHALLENGETYPE="${1}"
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
    revoke) command_revoke "${PARAM_REVOKECERT}";;
    *) command_help; exit 1;;
  esac
}

# Check for missing dependencies
check_dependencies

# Run script
main "${@:-}"
