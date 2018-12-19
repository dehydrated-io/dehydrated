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
# Example hook for deployment on MirBSD, with mbsdcert.sh from this
# directory serving as a filter for the incoming data.

print -nr -- "D: mbsdhook.sh invoked with: "
for i in "$@"; do
	print -nr -- "${i@Q} "
done
print -r -- "#"

case $1 {
(deploy_cert)
	# handled below
	;;
(startup_hook)
	if (( (${EPOCHREALTIME%.*} - $(stat -f %m /etc/ssl/default.cer)) > \
	    (66 * 86400) )); then
		print -ru2 'E: /etc/ssl/default.cer is older than 66 days, smells fishy'
	fi
	exit 0
	;;
(*)
	# nothing more to do
	exit 0
	;;
}

# 1=deploy_cert 2=domain 3=privkey 4=cert 5=cert+chain 6=chain 7=timestamp
print '# from mbsdhook.sh' | \
    cat - "$3" "$4" "$6" | \
    sudo /usr/local/libexec/mbsdcert.sh
# see there for the rest
