#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2018
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
# install -c -o 0 -g bin -m 555 docs/examples/kolab2-cert.sh /kolab/local/libexec/
# - and add to sudoers:
#  _acme	ALL = NOPASSWD: /kolab/local/libexec/kolab2-cert.sh

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
if [[ $line != '# from kolab2-hook.sh' ]]; then
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

if [[ -s /kolab/etc/kolab/dhparams.pem ]]; then
	dhp=$(</kolab/etc/kolab/dhparams.pem)$nl
else
	dhp=
fi

if [[ -s /usr/share/ca-bundle/certs/12d55845.0 ]]; then
	rCA=$(</usr/share/ca-bundle/certs/12d55845.0)$nl
else
	print -ru2 "E: root CA cert not found"
	exit 1
fi

dofile 0644 0:0 /kolab/etc/kolab/default.cer "$cer"
[[ -n $dhp ]] && dofile 0644 0:0 /kolab/etc/kolab/dhparams.pem "$dhp"
dofile 0644 kolab:kolab-r /kolab/etc/kolab/cert.pem "$cer$chn"
dofile 0644 kolab:kolab-r /kolab/etc/kolab/cert_plus_root.pem "$cer$chn$rCA"
dofile 0644 kolab:kolab-r /kolab/etc/kolab/chain.pem "$chn"
dofile 0644 kolab:kolab-r /kolab/etc/kolab/chain_plus_root.pem "$chn$rCA"
dofile 0640 kolab:kolab-r /kolab/etc/kolab/key.pem "$key$dhp"

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

print -ru2 "W: reboot this system within the next four weeks!"
exit 0
