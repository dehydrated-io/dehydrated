#!/usr/bin/env bash

# Fail early
set -eu -o pipefail

# Check if running in CI environment
if [[ ! "${CI:-false}" == "true" ]]; then
  echo "ERROR: Not running in CI environment!"
  exit 1
fi

_TEST() {
  echo
  echo "${1} "
}
_SUBTEST() {
  echo -n " + ${1} "
}
_PASS() {
  echo -e "[\u001B[32mPASS\u001B[0m]"
}
_FAIL() {
  echo -e "[\u001B[31mFAIL\u001B[0m]"
  echo
  echo "Problem: ${@}"
  echo
  echo "STDOUT:"
  cat tmplog
  echo
  echo "STDERR:"
  cat errorlog
  exit 1
}
_CHECK_FILE() {
  _SUBTEST "Checking if file '${1}' exists..."
  if [[ -e "${1}" ]]; then
    _PASS
  else
    _FAIL "Missing file: ${1}"
  fi
}
_CHECK_LOG() {
  _SUBTEST "Checking if log contains '${1}'..."
  if grep -- "${1}" tmplog > /dev/null; then
    _PASS
  else
    _FAIL "Missing in log: ${1}"
  fi
}
_CHECK_NOT_LOG() {
  _SUBTEST "Checking if log doesn't contain '${1}'..."
  if grep -- "${1}" tmplog > /dev/null; then
    _FAIL "Found in log: ${1}"
  else
    _PASS
  fi
}
_CHECK_ERRORLOG() {
  _SUBTEST "Checking if errorlog is empty..."
  if [[ -z "$(cat errorlog)" ]]; then
    _PASS
  else
    _FAIL "Non-empty errorlog"
  fi
}

# If not found (should be cached in travis) download ngrok
if [[ ! -e "ngrok/ngrok" ]]; then
  (
    mkdir -p ngrok
    cd ngrok
    wget https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip -O ngrok.zip
    unzip ngrok.zip ngrok
    chmod +x ngrok
  )
fi

# Run ngrok and grab temporary url from logfile
ngrok/ngrok http 8080 --log stdout --log-format logfmt --log-level debug > tmp.log &
ngrok/ngrok http 8080 --log stdout --log-format logfmt --log-level debug > tmp2.log &
ngrok/ngrok http 8080 --log stdout --log-format logfmt --log-level debug > tmp3.log &
sleep 2
TMP_URL="$(grep -Eo "Hostname:[a-z0-9]+.ngrok.io" tmp.log | head -1 | cut -d':' -f2)"
TMP2_URL="$(grep -Eo "Hostname:[a-z0-9]+.ngrok.io" tmp2.log | head -1 | cut -d':' -f2)"
TMP3_URL="$(grep -Eo "Hostname:[a-z0-9]+.ngrok.io" tmp3.log | head -1 | cut -d':' -f2)"
if [[ -z "${TMP_URL}" ]] || [[ -z "${TMP2_URL}" ]] || [[ -z "${TMP3_URL}" ]]; then
  echo "Couldn't get an url from ngrok, not a dehydrated bug, tests can't continue."
  exit 1
fi

# Run python webserver in .acme-challenges directory to serve challenge responses
mkdir -p .acme-challenges/.well-known/acme-challenge
(
  cd .acme-challenges
  python -m SimpleHTTPServer 8080 > /dev/null 2> /dev/null
) &

# Generate config and create empty domains.txt
echo 'CA="https://testca.kurz.pw/directory"' > config
echo 'CA_TERMS="https://testca.kurz.pw/terms"' >> config
echo 'WELLKNOWN=".acme-challenges/.well-known/acme-challenge"' >> config
echo 'RENEW_DAYS="14"' >> config
touch domains.txt

# Check if help command is working
_TEST "Checking if help command is working..."
./dehydrated --help > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Default command: help"
_CHECK_LOG "--help (-h)"
_CHECK_LOG "--domain (-d) domain.tld"
_CHECK_ERRORLOG

# Register account key without LICENSE set
_TEST "Register account key without LICENSE set"
./dehydrated --register > tmplog 2> errorlog && _FAIL "Script execution failed"
_CHECK_LOG "To accept these terms"
_CHECK_ERRORLOG

# Register account key and agreeing to terms
_TEST "Register account key without LICENSE set"
./dehydrated --register --accept-terms > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Registering account key"
_CHECK_FILE accounts/*/account_key.pem
_CHECK_ERRORLOG

# Delete accounts and add LICENSE to config for normal operation
rm -rf accounts
echo 'LICENSE="https://testca.kurz.pw/terms/v1"' >> config

# Run in cron mode with empty domains.txt (should only generate private key and exit)
_TEST "First run in cron mode, checking if private key is generated and registered"
./dehydrated --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Registering account key"
_CHECK_FILE accounts/*/account_key.pem
_CHECK_ERRORLOG

# Temporarily move config out of the way and try signing certificate by using temporary config location
_TEST "Try signing using temporary config location and with domain as command line parameter"
mv config tmp_config
./dehydrated --cron --domain "${TMP_URL}" --domain "${TMP2_URL}" --accept-terms -f tmp_config > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_NOT_LOG "Checking domain name(s) of existing cert"
_CHECK_LOG "Generating private key"
_CHECK_LOG "Requesting challenge for ${TMP_URL}"
_CHECK_LOG "Requesting challenge for ${TMP2_URL}"
_CHECK_LOG "Challenge is valid!"
_CHECK_LOG "Creating fullchain.pem"
_CHECK_LOG "Done!"
_CHECK_ERRORLOG
mv tmp_config config

# Add third domain to command-lime, should force renewal.
_TEST "Run in cron mode again, this time adding third domain, should force renewal."
./dehydrated --cron --domain "${TMP_URL}" --domain "${TMP2_URL}" --domain "${TMP3_URL}" > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Domain name(s) are not matching!"
_CHECK_LOG "Forcing renew."
_CHECK_LOG "Generating private key"
_CHECK_LOG "Requesting challenge for ${TMP_URL}"
_CHECK_LOG "Requesting challenge for ${TMP2_URL}"
_CHECK_LOG "Requesting challenge for ${TMP3_URL}"
_CHECK_LOG "Challenge is valid!"
_CHECK_LOG "Creating fullchain.pem"
_CHECK_LOG "Done!"
_CHECK_ERRORLOG

# Prepare domains.txt
# Modify TMP3_URL to be uppercase to check for upper-lower-case mismatch bugs
echo "${TMP_URL} ${TMP2_URL} $(tr 'a-z' 'A-Z' <<<"${TMP3_URL}")" >> domains.txt

# Run in cron mode again (should find a non-expiring certificate and do nothing)
_TEST "Run in cron mode again, this time with domain in domains.txt, should find non-expiring certificate"
./dehydrated --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Checking domain name(s) of existing cert... unchanged."
_CHECK_LOG "Skipping renew"
_CHECK_ERRORLOG

# Disable private key renew
echo 'PRIVATE_KEY_RENEW="no"' >> config

# Run in cron mode one last time, with domain in domains.txt and force-resign (should find certificate, resign anyway, and not generate private key)
_TEST "Run in cron mode one last time, with domain in domains.txt and force-resign"
./dehydrated --cron --force > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Checking domain name(s) of existing cert... unchanged."
_CHECK_LOG "Ignoring because renew was forced!"
_CHECK_NOT_LOG "Generating private key"
_CHECK_LOG "Requesting challenge for ${TMP_URL}"
_CHECK_LOG "Requesting challenge for ${TMP2_URL}"
_CHECK_LOG "Requesting challenge for ${TMP3_URL}"
_CHECK_LOG "Already validated!"
_CHECK_LOG "Creating fullchain.pem"
_CHECK_LOG "Done!"
_CHECK_ERRORLOG

# Check if signcsr command is working
_TEST "Running signcsr command"
./dehydrated --signcsr certs/${TMP_URL}/cert.csr > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "BEGIN CERTIFICATE"
_CHECK_LOG "END CERTIFICATE"
_CHECK_NOT_LOG "ERROR"

# Check if renewal works
_TEST "Run in cron mode again, to check if renewal works"
echo 'RENEW_DAYS="300"' >> config
./dehydrated --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Checking domain name(s) of existing cert... unchanged."
_CHECK_LOG "Renewing!"
_CHECK_ERRORLOG

# Check if certificate is valid in various ways
_TEST "Verifying certificate..."
_SUBTEST "Verifying certificate on its own..."
openssl x509 -in "certs/${TMP_URL}/cert.pem" -noout -text > tmplog 2> errorlog && _PASS || _FAIL
_CHECK_LOG "CN=${TMP_URL}"
_CHECK_LOG "${TMP2_URL}"
_SUBTEST "Verifying file with full chain..."
openssl x509 -in "certs/${TMP_URL}/fullchain.pem" -noout -text > /dev/null 2>> errorlog && _PASS || _FAIL
_SUBTEST "Verifying certificate against CA certificate..."
curl -s https://testca.kurz.pw/acme/issuer-cert | openssl x509 -inform DER -outform PEM > ca.pem
(openssl verify -verbose -CAfile "ca.pem" -purpose sslserver "certs/${TMP_URL}/fullchain.pem" 2>&1 || true) | (grep -v ': OK$' || true) >> errorlog 2>> errorlog && _PASS || _FAIL
_CHECK_ERRORLOG

# Revoke certificate using certificate key
_TEST "Revoking certificate..."
./dehydrated --revoke "certs/${TMP_URL}/cert.pem" --privkey "certs/${TMP_URL}/privkey.pem" > tmplog 2> errorlog || _FAIL "Script execution failed"
REAL_CERT="$(readlink -n "certs/${TMP_URL}/cert.pem")"
_CHECK_LOG "Revoking certs/${TMP_URL}/${REAL_CERT}"
_CHECK_LOG "Done."
_CHECK_FILE "certs/${TMP_URL}/${REAL_CERT}-revoked"
_CHECK_ERRORLOG

# Enable private key renew
echo 'PRIVATE_KEY_RENEW="yes"' >> config
echo 'PRIVATE_KEY_ROLLOVER="yes"' >> config

# Check if Rolloverkey creation works
_TEST "Testing Rolloverkeys..."
_SUBTEST "First Run: Creating rolloverkey"
./dehydrated --cron --domain "${TMP2_URL}" > tmplog 2> errorlog || _FAIL "Script execution failed"
CERT_ROLL_HASH=$(openssl rsa -in certs/${TMP2_URL}/privkey.roll.pem -outform DER -pubout 2>/dev/null | openssl sha256)
_CHECK_LOG "Generating private key"
_CHECK_LOG "Generating private rollover key"
_SUBTEST "Second Run: Force Renew, Use rolloverkey"
./dehydrated --cron --force --domain "${TMP2_URL}" > tmplog 2> errorlog || _FAIL "Script execution failed"
CERT_NEW_HASH=$(openssl rsa -in certs/${TMP2_URL}/privkey.pem -outform DER -pubout 2>/dev/null | openssl sha256)
_CHECK_LOG "Generating private key"
_CHECK_LOG "Moving Rolloverkey into position"
_SUBTEST "Verifying Hash Rolloverkey and private key second run"
[[ "${CERT_ROLL_HASH}" = "${CERT_NEW_HASH}" ]] && _PASS || _FAIL
_CHECK_ERRORLOG

# Test cleanup command
_TEST "Cleaning up certificates"
./dehydrated --cleanup > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Moving unused file to archive directory: ${TMP_URL}/cert-"
_CHECK_LOG "Moving unused file to archive directory: ${TMP_URL}/chain-"
_CHECK_LOG "Moving unused file to archive directory: ${TMP_URL}/fullchain-"
_CHECK_ERRORLOG

# All done
exit 0
