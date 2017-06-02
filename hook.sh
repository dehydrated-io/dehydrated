#!/bin/bash

function deploy_challenge {
    local domains=("$@") 
    aLen=${#domains[@]} 

    cd tools/

    for (( i=0; i<${aLen}; i=i+3));
    do
        j=i+2
        python route53_txt_record.py -a create -d ${domains[$i]} -t ${domains[$j]}
    done
    sleep 15

}

function clean_challenge {
    local domains=("$@") 
    aLen=${#domains[@]} 

    cd tools/

    for (( i=0; i<${aLen}; i=i+3));
    do
        j=i+2
        python route53_txt_record.py -a delete -d ${domains[$i]} -t ${domains[$j]}
    done
}

function deploy_cert {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}"

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
    # - CHAINFILE
    #   The path of the file containing the full certificate chain.

    cd tools/
    python certs_to_s3.py -d $DOMAIN -k $KEYFILE -c $FULLCHAINFILE -f $FULLCHAINFILE
}

function unchanged_cert {
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

exit_hook() {
  # This hook is called at the end of a dehydrated command and can be used
  # to do some final (cleanup or other) tasks.

  :
}

HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert|unchanged_cert|invalid_challenge|request_failure|exit_hook)$ ]]; then
  "$HANDLER" "$@"
fi
