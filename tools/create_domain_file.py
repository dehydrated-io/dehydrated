#! /usr/bin/env python
'''
Creates the domains.txt file by looking at all deployed shas and creating a single domain file for cert creation/reinstallation.    
'''

import sys
import getopt
from boto.s3.connection import S3Connection
from boto.s3.key import Key
from time import sleep

help_text = 'create_domain_file.py -d [domain] -f [filename]'

def subdomain_from_repo(repo):
    switcher = {
        'auth': "login",
        'learning': "live",
        'toys': "apps",
        'toychest': "store",
        'lightyear': "room",
        'techcheck': "setup",
    }

    return switcher.get(repo, "nothing")


def create_domain_string(domain, subdomain, new_treeish):
    if domain == "presencetest.com":
        flavor = "test"
    else:
        flavor = "live"

    s3 = S3Connection()
    s3_bucket = s3.get_bucket('presencelearning-devops')

    s3_bucket_list = s3_bucket.list(prefix="deploy/" + flavor + "-app/deployed_hashes/")

    deployed_list = [domain, 'kidinsight.' + domain, 'room.' + domain, 'store.' + domain, 'apps.' + domain, 'setup.' + domain, 'login.' + domain, 'test.' + domain, 'live.' + domain]
    deployed_set = set({})

    if subdomain == 'test' or subdomain == 'live':
        deployed_set.add("{treeish}.test.{domain}".format(treeish=new_treeish, domain=domain))
        deployed_set.add("{treeish}.live.{domain}".format(treeish=new_treeish, domain=domain))
    else:
        deployed_set.add('{treeish}.{subdomain}.{domain}'.format(treeish=new_treeish, subdomain=subdomain, domain=domain))

    for key in s3_bucket_list:
        key_list = key.name.split('/')
        if key_list[3]: 
            s3_key = s3_bucket.get_key(key)
            active_list = key_list[3].split('_')
            repo = active_list[0]
            treeish = active_list[1]

            if repo == 'bopeep' or repo == 'clinicianportal':
                continue

            if repo == 'learning':
                deployed_set.add("{treeish}.test.{domain}".format(treeish=treeish, domain=domain))
                deployed_set.add("{treeish}.live.{domain}".format(treeish=treeish, domain=domain))
            else:
                deployed_set.add("{treeish}.{subdomain}.{domain}".format(treeish=treeish, subdomain=subdomain_from_repo(repo), domain=domain))

    return " ".join(deployed_list) + "" + " ".join(deployed_set) 

def create_domain_textfile(domain, filename):
    domain_parts = domain.split('.')
    treeish = domain_parts[-4]
    subdomain = domain_parts[-3]
    tld = domain_parts[-2] + '.' + domain_parts[-1]

    textfile_string = create_domain_string(tld, subdomain, treeish) 
    with open(filename, "w") as text_file:
        text_file.write("{}".format(textfile_string))


def parse_and_run(argv):
    try:
        opts, args = getopt.getopt(argv,"hd:f:")
    except getopt.GetoptError:
        print help_text
        sys.exit(2)

    for opt, arg in opts:
        if opt == '-h':
            print help_text
            sys.exit(0)
        elif opt in ("-d"):
            domain = arg
        elif opt in ("-f"):
            filename = arg

    if not domain or not filename:
        print help_text
        sys.exit(0)

    create_domain_textfile(domain, filename)


if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_and_run(sys.argv[1:])
    else:
        print help_text
        sys.exit(0)
