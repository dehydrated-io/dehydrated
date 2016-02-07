#! /usr/bin/env python
'''
    This script allows you to set a TXT record in Route53 so that LetsEncrypt can validate our certs requests.
    The record can also be deleted.
'''

import sys
import getopt
from boto import route53
from time import sleep

help_text = 'route53_txt_record.py -a <create|delete> -d [fqd] -t [token]'

def route53_connect():
    return route53.connect_to_region('us-west-2') 

def get_zone_name(fqd):
    domain_parts = fqd.split('.')
    zone_name = "{domain}.{tld}.".format(domain=domain_parts[-2], tld=domain_parts[-1])

    return zone_name

def create_txt_record(fqd, token):
    zone_name = get_zone_name(fqd)
    conn = route53_connect()
    zone = conn.get_zone(zone_name)
    status = zone.add_record("TXT", "_acme-challenge." + fqd, '"{token}"'.format(token=token), ttl=60)

    while status == "PENDING":
        status.update()
        sleep(0.5)

    sleep(10)


def delete_txt_record(fqd, token):
    zone_name = get_zone_name(fqd)
    conn = route53_connect()
    zone = conn.get_zone(zone_name)
    record = zone.find_records("_acme-challenge." + fqd, "TXT", desired=1, all=False)
    zone.delete_record(record)

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
            fqd = arg
        elif opt in ("-t"):
            token = arg

    if not action or not fqd or not token:
        print help_text
        sys.exit(0)

    if action == 'create':
        create_txt_record(fqd, token)
    elif action == 'delete': 
        delete_txt_record(fqd, token)
    else:
        print "Action not recognized."
        print help_text
        sys.exit(0)


if __name__ == '__main__':
    if len(sys.argv) > 1:
        parse_and_run(sys.argv[1:])
    else:
        print help_text
        sys.exit(0)
