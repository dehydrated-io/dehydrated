#! /usr/bin/env python
'''
    This script allows you to set a TXT record in Route53 so that LetsEncrypt can validate our certs requests.
    The record can also be removed.
'''

import sys
import getopt
from boto.s3.connection import S3Connection
from boto.s3.key import Key

help_text = 'certs_to_s3.py -a <add|remove> -d [domain] -t [token]'

def copy_file_to_s3(self):
	s3 = S3Connection()
	s3_bucket = s3.get_bucket('presencelearning-devops')

	s3_key = Key(s3_bucket)
	s3_key.key = 'deploy/{flavor}-app/deployed_hashes/{repo}_{treeish}'.format(flavor=self._flavor, repo=self._repo, treeish=self._treeish)
	#s3_key.set_contents_from_string(self._metadata)
	s3_key.set_contents_from_filename('foo.jpg')

def parse_and_run(argv):
    try:
        opts, args = getopt.getopt(argv,"ha:d:t:")
    except getopt.GetoptError:
        print help_text
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print help_text
            sys.exit(0)
        elif opt in ("-a"):
            action = arg
        elif opt in ("-d"):
            domain = arg
        elif opt in ("-t"):
            token = arg

    if not action or not domain or not token:
        print help_text
        sys.exit(0)


if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_and_run(sys.argv[1:])
    else:
        print help_text
        sys.exit(0)
