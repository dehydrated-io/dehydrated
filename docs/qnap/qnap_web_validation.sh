WEBROOT=/share/$(/sbin/getcfg SHARE_DEF defWeb -d Qweb -f /etc/config/def_share.info)
WELLKNOWN=${WEBROOT}/.well-known/acme-challenges
mkdir -p ${WELLKNOWN}
