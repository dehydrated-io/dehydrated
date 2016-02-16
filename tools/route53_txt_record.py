#! /usr/bin/env python
'''
    This script allows you to set a TXT record in Route53 so that LetsEncrypt can validate our certs requests.
    The record can also be deleted.
'''

import sys
import getopt
from boto import route53
from time import sleep

help_text = 'route53_txt_record.py -a <create|update|delete|batchcreate> -d [fqd] -f [domain_file] -t [token]'

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
    status = zone.add_record("TXT", "_acme-challenge." + fqd, '"{token}"'.format(token=token), ttl=1)

    print "Add {domain} to Route53".format(domain=fqd)    

#    while True:
#        print status
#        if status.update() == "INSYNC":
#            break
#        sleep(0.1)

def delete_txt_record(fqd, token):
    zone_name = get_zone_name(fqd)
    conn = route53_connect()
    zone = conn.get_zone(zone_name)
    record = zone.find_records("_acme-challenge." + fqd, "TXT", desired=1, all=False)
    zone.delete_record(record)

def update_txt_record(fqd, token):
    zone_name = get_zone_name(fqd)
    conn = route53_connect()
    zone = conn.get_zone(zone_name)
    record = zone.find_records("_acme-challenge." + fqd, "TXT")
    if record:
        status = zone.update_record(record, '"{token}"'.format(token=token))
    else:
        status = zone.add_record("TXT", "_acme-challenge." + fqd, '"{token}"'.format(token=token), ttl=1)
    print "Update {domain}".format(domain=fqd)    

def batch_create_txt_record(domain_file, token):
    with open(domain_file, 'r') as dfile:
        domain_string=dfile.read().replace('\n', '')

        for domain in domain_string.split():
            zone_name = get_zone_name(domain)
            conn = route53_connect()
            zone = conn.get_zone(zone_name)
            status = zone.add_record("TXT", "_acme-challenge." + domain, '"{token}"'.format(token=token), ttl=1)


def parse_and_run(argv):
    fqd = None
    domain_file = None
    try:
        opts, args = getopt.getopt(argv,"ha:d:f:t:")
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
        elif opt in ("-f"):
            domain_file = arg
        elif opt in ("-t"):
            token = arg

    if not fqd and not domain_file:
        print help_text
        sys.exit(0)
    if not action or not token:
        print help_text
        sys.exit(0)

    if action == 'create':
        create_txt_record(fqd, token)
    elif action == 'delete': 
        delete_txt_record(fqd, token)
    elif action == 'update': 
        update_txt_record(fqd, token)
    elif action == 'batchcreate': 
        batch_create_txt_record(domain_file, token)
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
