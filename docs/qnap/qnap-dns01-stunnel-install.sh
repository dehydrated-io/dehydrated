#!/usr/bin/env bash

# This hook is called once for every domain that needs to be
# validated, including any alternative names you may have listed.
function deploy_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    echo "Create the following DNS record:"
    echo "_acme-challenge.${DOMAIN}.      300 IN TXT \"${TOKEN_VALUE}\""
    echo ""
    echo "Hit [ENTER] when DNS entries have been created"
    read -s -r -e < /dev/tty

    # Now check DNS results
    RESULT=$(dig +short _acme-challenge.${DOMAIN}. TXT 2> /dev/null | sed -e 's/^"//' | sed -e 's/"$//')
    if [[ $RESULT != $TOKEN_VALUE ]]; then
      echo ""
      echo "Either dig command is not installed, or the expected result is not available in DNS yet."
      echo "Please fix and retest manually using this command on another host:"
      echo "    dig _acme-challenge.${DOMAIN}. TXT"
      echo ""
      echo "Hit [ENTER] when you see the correct value returned."
      read -s -r -e < /dev/tty
    fi
}

function clean_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"

    echo ""
    echo "You may now remove DNS records which start with _acme-challenge and have this value: ${TOKEN_VALUE}"
    echo ""
}

# This hook is called once for each certificate that has been
# produced. Here you might, for instance, copy your new certificates
# to service-specific locations and reload the service.
function deploy_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
    cp /etc/stunnel/stunnel.pem /etc/stunnel/stunnel.pem-$(date +%Y%m%d)
    cat $KEYFILE $FULLCHAINFILE > /etc/stunnel/stunnel.pem
    /etc/init.d/stunnel.sh restart
}

# This hook is called once for each certificate that is still
# valid and therefore wasn't reissued.
function unchanged_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"
}

HANDLER=$1; shift; $HANDLER $@
