#!/bin/bash

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
  if [[ ! -z "$(cat errorlog)" ]]; then
    _FAIL
  fi
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
    cd ngrog
    wget https://dl.ngrok.com/ngrok_2.0.19_linux_amd64.zip -O ngrok.zip
    unzip ngrok.zip ngrok
    chmod +x ngrok
  )
fi

# Run ngrok and grab temporary url from logfile
ngrok/ngrok http 8080 --log stdout --log-format logfmt --log-level debug > tmp.log &
ngrok/ngrok http 8080 --log stdout --log-format logfmt --log-level debug > tmp2.log &
sleep 2
TMP_URL="$(grep -Eo "Hostname:[a-z0-9]+.ngrok.io" tmp.log | head -1 | cut -d':' -f2)"
TMP2_URL="$(grep -Eo "Hostname:[a-z0-9]+.ngrok.io" tmp2.log | head -1 | cut -d':' -f2)"
if [[ -z "${TMP_URL}" ]] || [[ -z "${TMP2_URL}" ]]; then
  echo "Couldn't get an url from ngrok, not a letsencrypt.sh bug, tests can't continue."
  exit 1
fi

# Run python webserver in .acme-challenges directory to serve challenge responses
mkdir -p .acme-challenges/.well-known/acme-challenge
(
  cd .acme-challenges
  python -m SimpleHTTPServer 8080 > /dev/null 2> /dev/null
) &

# Generate config and create empty domains.txt
echo 'CA="https://testca.kurz.pw/directory"' > config.sh
echo 'LICENSE="https://testca.kurz.pw/terms/v1"' >> config.sh
echo 'WELLKNOWN=".acme-challenges/.well-known/acme-challenge"' >> config.sh
touch domains.txt

# Check if help command is working
_TEST "Checking if help command is working..."
./letsencrypt.sh --help > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Default command: help"
_CHECK_LOG "--help (-h)"
_CHECK_LOG "--domain (-d) domain.tld"
_CHECK_ERRORLOG

# Run in cron mode with empty domains.txt (should only generate private key and exit)
_TEST "First run in cron mode, checking if private key is generated and registered"
./letsencrypt.sh --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Registering account key"
_CHECK_FILE "private_key.pem"
_CHECK_ERRORLOG

# Temporarily move config out of the way and try signing certificate by using temporary config location
_TEST "Try signing using temporary config location and with domain as command line parameter"
mv config.sh tmp_config.sh
./letsencrypt.sh --cron --domain "${TMP_URL} ${TMP2_URL}" -f tmp_config.sh > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_NOT_LOG "Checking domain name(s) of existing cert"
_CHECK_LOG "Generating private key"
_CHECK_LOG "Requesting challenge for ${TMP_URL}"
_CHECK_LOG "Requesting challenge for ${TMP2_URL}"
_CHECK_LOG "Challenge is valid!"
_CHECK_LOG "Creating fullchain.pem"
_CHECK_LOG "Done!"
_CHECK_ERRORLOG
mv tmp_config.sh config.sh

# Move private key and add new location to config
mv private_key.pem account_key.pem
echo 'PRIVATE_KEY="./account_key.pem"' >> config.sh

# Add domain to domains.txt and run in cron mode again (should find a non-expiring certificate and do nothing)
_TEST "Run in cron mode again, this time with domain in domains.txt, should find non-expiring certificate"
echo "${TMP_URL} ${TMP2_URL}" >> domains.txt
./letsencrypt.sh --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Checking domain name(s) of existing cert... unchanged."
_CHECK_LOG "Skipping!"
_CHECK_ERRORLOG

# Run in cron mode one last time, with domain in domains.txt and force-resign (should find certificate, resign anyway, and not generate private key)
_TEST "Run in cron mode one last time, with domain in domains.txt and force-resign"
./letsencrypt.sh --cron --force > tmplog 2> errorlog || _FAIL "Script execution failed"
_CHECK_LOG "Checking domain name(s) of existing cert... unchanged."
_CHECK_LOG "Ignoring because renew was forced!"
_CHECK_NOT_LOG "Generating private key"
_CHECK_LOG "Requesting challenge for ${TMP_URL}"
_CHECK_LOG "Requesting challenge for ${TMP2_URL}"
_CHECK_LOG "Challenge is valid!"
_CHECK_LOG "Creating fullchain.pem"
_CHECK_LOG "Done!"
_CHECK_ERRORLOG

# Delete account key (not needed anymore)
rm account_key.pem

# Check if renewal works
_TEST "Run in cron mode again, to check if renewal works"
echo 'RENEW_DAYS="300"' >> config.sh
./letsencrypt.sh --cron > tmplog 2> errorlog || _FAIL "Script execution failed"
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
(openssl verify -verbose -CAfile "certs/${TMP_URL}/fullchain.pem" -purpose sslserver "certs/${TMP_URL}/fullchain.pem" 2>&1 || true) | (grep -v ': OK$' || true) >> errorlog 2>> errorlog && _PASS || _FAIL
_CHECK_ERRORLOG

# Revoke certificate using certificate key
_TEST "Revoking certificate..."
./letsencrypt.sh --revoke "certs/${TMP_URL}/cert.pem" --privkey "certs/${TMP_URL}/privkey.pem" > tmplog 2> errorlog || _FAIL "Script execution failed"
REAL_CERT="$(readlink -n "certs/${TMP_URL}/cert.pem")"
_CHECK_LOG "Revoking certs/${TMP_URL}/${REAL_CERT}"
_CHECK_LOG "SUCCESS"
_CHECK_FILE "certs/${TMP_URL}/${REAL_CERT}-revoked"
_CHECK_ERRORLOG

# All done
exit 0
