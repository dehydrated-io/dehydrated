if [[ -f /etc/ssl/certs/ca-certificates.crt ]]
then
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
else
    if [[ ! -f /etc/ssl/certs/cabundle.pem ]]
    then
        wget --quiet --no-check-certificate -O /etc/ssl/certs/cabundle.pem https://curl.haxx.se/ca/cacert.pem
    fi
    export SSL_CERT_FILE=/etc/ssl/certs/cabundle.pem
fi
