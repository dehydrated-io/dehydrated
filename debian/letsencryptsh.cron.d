#
# Regular cron jobs for the letsencryptsh package
#
0 4	* * *	root	[ -x /usr/bin/letsencrypt-sh ] && /usr/bin/letsencrypt-sh -c > /dev/null
