#! /usr/bin/env python
'''
    This script allows you to set a TXT record in Route53 so that LetsEncrypt can validate our certs requests.
    The record can also be removed.
'''

import sys
import getopt
from boto.s3.connection import S3Connection
from boto.s3.key import Key

help_text = 'certs_to_s3.py -d [domain] -k [keyfile] -c [certfile]'

def copy_file_to_s3(localfile, filename):
    s3 = S3Connection()
    s3_bucket = s3.get_bucket('presencelearning-devops')

    s3_key = Key(s3_bucket)
    s3_key.key = filename 
    s3_key.set_contents_from_filename(localfile, encrypt_key=True)

def get_filename_flavor(domain):
    domain_parts = domain.split('.')
    if domain_parts[-2] == 'presencelearning':
        flavor = 'live'
    else:
        flavor = 'test'

    return "presence_{flavor}".format(flavor=flavor), flavor

def parse_and_run(argv):
    try:
        opts, args = getopt.getopt(argv,"hd:k:c:")
    except getopt.GetoptError:
        print help_text
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print help_text
            sys.exit(0)
        elif opt in ("-d"):
            domain = arg
        elif opt in ("-k"):
            keyfile = arg
        elif opt in ("-c"):
            certfile = arg

    if not domain or not keyfile or not certfile:
        print help_text
        sys.exit(0)


    filename, flavor = get_filename_flavor(domain)
    copy_file_to_s3('.' + certfile, "letsencrypt/{flavor}-app/certs/{filename}.crt".format(flavor=flavor, filename=filename))
    copy_file_to_s3('.' + keyfile, "letsencrypt/{flavor}-app/keys/{filename}.key".format(flavor=flavor, filename=filename))
    copy_file_to_s3('.fullchain.pem', "letsencrypt/{flavor}-app/keys/fullchain.pem")


if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_and_run(sys.argv[1:])
    else:
        print help_text
        sys.exit(0)
