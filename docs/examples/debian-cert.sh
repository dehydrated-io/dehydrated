#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2018, 2019
#	mirabilos <mirabilos@evolvis.org>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# “Software”), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#-
# mkdir -p /usr/local/libexec
# install -c -o 0 -g 0 -m 555 docs/examples/debian-cert.sh /usr/local/libexec/
# - and add to sudoers:
#  _acme	ALL = NOPASSWD: /usr/local/libexec/debian-cert.sh

set -e
set -o pipefail
umask 077
cd /
set +e

if (( USER_ID )); then
	print -ru2 E: need root
	exit 1
fi

IFS= read -r line
if [[ $line != '# from debian-hook.sh' ]]; then
	print -ru2 E: not called from dehydrated hook script
	exit 1
fi

nl=$'\n'
key=
cer=
chn=
buf=
s=0

while IFS= read -r line; do
	buf+=$line$nl
	[[ $line = '-----END'* ]] || continue
	case $s {
	(0)
		if ! key=$(print -nr -- "$buf" | \
		    sudo -u nobody openssl rsa) 2>&1; then
			print -ru2 E: could not read private key
			exit 1
		fi
		key+=$nl
		s=1
		;;
	(*)
		if ! line=$(print -nr -- "$buf" | \
		    sudo -u nobody openssl x509) 2>&1; then
			print -ru2 E: could not read certificate $s
			exit 1
		fi
		if (( s == 1 )); then
			cer=$line$nl
		else
			chn+=$line$nl
		fi
		s=2
		;;
	}
	buf=
done

case $s {
(0)
	print -ru2 -- E: private key missing
	exit 1
	;;
(1)
	print -ru2 -- E: certificate missing
	exit 1
	;;
(2)
	if [[ -z $chn ]]; then
		print -ru2 -- E: expected a chain of at least length 1
		exit 1
	fi
	;;
(*)
	print -ru2 -- E: cannot happen
	exit 255
	;;
}

set -A rename_src
set -A rename_dst
nrenames=0
rv=0

function dofile {
	local mode=$1 owner=$2 name=$3 content=$4 fn

	(( rv )) && return

	if ! fn=$(mktemp "$name.XXXXXXXXXX"); then
		print -ru2 "E: cannot create temporary file for $name"
		rv=2
		return
	fi
	rename_src[nrenames]=$fn
	rename_dst[nrenames++]=$name
	chown "$owner" "$fn"
	chmod "$mode" "$fn"
	print -nr -- "$content" >"$fn"
}

if [[ -s /etc/ssl/dhparams.pem ]]; then
	dhp=$(</etc/ssl/dhparams.pem)$nl
else
	dhp=
fi

dofile 0644 0:0 /etc/ssl/default.cer "$cer$dhp"
dofile 0644 0:0 /etc/ssl/default.ca "$chn"
[[ -n $dhp ]] && dofile 0644 0:0 /etc/ssl/dhparams.pem "$dhp"
dofile 0644 0:0 /etc/ssl/deflt+ca.pem "$cer$chn" #XXX append $dhp ?
dofile 0640 0:ssl-cert /etc/ssl/private/default.key "$key"
dofile 0640 0:ssl-cert /etc/ssl/private/deflt+ca.pem "$key$cer$chn" #XXX append $dhp ?

if (( rv )); then
	rm -f "${rename_src[@]}"
	exit $rv
fi

while (( nrenames-- )); do
	if ! mv "${rename_src[nrenames]}" "${rename_dst[nrenames]}"; then
		print -ru2 "E: rename ${rename_src[nrenames]@Q}" \
		    "${rename_dst[nrenames]@Q} failed ⇒ system hosed"
		exit 3
	fi
done

readonly p=/bin:/usr/bin:/sbin:/usr/sbin
rc=0
function svr {
	local rv iserr=$1; shift
	/usr/bin/env -i PATH=$p HOME=/ "$@" 2>&1
	rv=$?
	(( rv )) && if (( iserr )); then
		print -ru2 "E: errorlevel $rv trying to $*"
		rc=1
	else
		print -ru1 "W: errorlevel $rv trying to $*"
	fi
}

# restart affected services
svr 0 /etc/init.d/apache2 stop
svr 1 /etc/init.d/postfix restart
svr 1 /etc/init.d/apache2 start
exit $rc
