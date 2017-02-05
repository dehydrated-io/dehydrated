#!/usr/bin/env bash

# This hook is called once for every domain that needs to be
# validated, including any alternative names you may have listed.
function deploy_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
}

function clean_challenge {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}"
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
