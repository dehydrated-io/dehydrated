#!/bin/sh

deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    # This hook is called once for every domain that needs to be
    # validated, including any alternative names you may have listed.
    #
    # Parameters:
    # - DOMAIN
    #   The domain name (CN or subject alternative name) being
    #   validated.
    # - TOKEN_FILENAME
    #   The name of the file containing the token to be served for HTTP
    #   validation. Should be served by your web server as
    #   /.well-known/acme-challenge/${TOKEN_FILENAME}.
    # - TOKEN_VALUE
    #   The token value that needs to be served for validation. For DNS
    #   validation, this is what you want to put in the _acme-challenge
    #   TXT record. For HTTP validation it is the value that is expected
    #   be found in the $TOKEN_FILENAME file.
}

clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    # This hook is called after attempting to validate each domain,
    # whether or not validation was successful. Here you can delete
    # files or DNS records that are no longer needed.
    #
    # The parameters are the same as for deploy_challenge.
}

deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    # - TIMESTAMP
    #   Timestamp when the specified certificate was created.


	### Below is the script to generate certificate pinning files.
	### To do that properly you MUST have any CSR generated for given $DOMAIN in associated folder.
	### The first "if" checks allows to include domains which do not require certificate pinning.
	### To completely bypass pinning generator script replace the first string with
	### 
	### if [[ ! ${DOMAIN} == *"..."* ]]; then
	###
	### that "if" will always give "false" as domain name cannot contain triple dots "..."
	###
	
	if [[ ! ${DOMAIN} == *"SPECIAL.COM"* ]]; then

		echo " + Generating HPKP information..."

		case "${KEY_ALGO}" in
			rsa) hpkp="$(openssl rsa -in ${BASEDIR}/certs/${DOMAIN}/privkey.pem -outform der -pubout 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64)";;
			prime256v1|secp384r1) hpkp="$(openssl ec -in ${BASEDIR}/certs/${DOMAIN}/privkey.pem -outform der -pubout 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64)";;
		esac

		hpbkp="$(openssl req -pubkey < ${BASEDIR}/certs/${DOMAIN}/backup.csr | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64)"

		thekey="pin-sha256="\""$hpkp"\""; "
		thekey2="pin-sha256="\""$hpbkp"\""; "
		tmpa="add_header public-key-pins '"$thekey$thekey2
		tmpb="max-age=2678400; includeSubDomains;';"

		tmpc=$tmpa$tmpb

		echo $tmpc > "${BASEDIR}/certs/${DOMAIN}/hpkp-${TIMESTAMP}.txt"
		ln -sf "${BASEDIR}/certs/${DOMAIN}/hpkp-${TIMESTAMP}.txt" "${BASEDIR}/certs/${DOMAIN}/hpkp.txt"
	else
		echo "nothing yet"
	fi

	### END of Certificate pinning script
	
# Testing Nginx config and reloading after new certificate issued
/usr/sbin/nginx -t && /usr/sbin/nginx -s reload || echo "NGINX CONFIG WRONG!"

}

unchanged_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

    # This hook is called once for each certificate that is still
    # valid and therefore wasn't reissued.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
}

invalid_challenge() {
    local DOMAIN="${1}" RESPONSE="${2}"

    # This hook is called if the challenge response has failed, so domain
    # owners can be aware and act accordingly.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - RESPONSE
    #   The response that the verification server returned

    logger LetsEncrypt CHALLENGE failure $DOMAIN $RESPONSE
}

request_failure() {
    local STATUSCODE="${1}" REASON="${2}" REQTYPE=${3}

    # This hook is called when a HTTP request fails (e.g., when the ACME
    # server is busy, returns an error, etc). It will be called upon any
    # response code that does not start with '2'. Useful to alert admins
    # about problems with requests.
    #
    # Parameters:
    # - STATUSCODE
    #   The HTML status code that originated the error.
    # - REASON
    #   The specified reason for the error.
    # - REQTYPE
    #   The kind of request that was made (GET, POST...)

    logger LetsEncrypt REQUEST failure $STATUSCODE $REASON $REQTYPE
}

exit_hook() {
  # This hook is called at the end of a dehydrated command and can be used
  # to do some final (cleanup or other) tasks.

  :
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
