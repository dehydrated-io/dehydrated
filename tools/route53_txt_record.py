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

def parse_domains(domains):
    #presencestag.com bsDx_WNkm-NWWI-a1bg2Mhl10JcSUnUlL6DaYZKXTZU JEXW4L4PkzMP6yRrPudTGRcpIwW-BFbtqaS34jQkGZI www.presencestag.com Pkhq50AMRdqIATUc0n5vSIxEPS_rO7eOCkwL61vfLJc qy0PwBWnWa7hujLkRunxZfuKDnCKCf4s1IPL858-AjM
    domain_dict = {}
    domain_token_list = domains.split(' ')
    while len(domain_token_list) > 0:
        token_end = domain_token_list.pop()
        token_start = domain_token_list.pop()
        fqd = domain_token_list.pop()
        domain_dict[fqd] = token_end 

    return domain_dict

def create_txt_record(domains):
    status_collection = []
    domain_dict = parse_domains(domains)
    conn = route53_connect()
    for fqd, token in domain_dict.iteritems():
        zone_name = get_zone_name(fqd)
        zone = conn.get_zone(zone_name)
        status = zone.add_record("TXT", "_acme-challenge." + fqd, '"{token}"'.format(token=token), ttl=1)
        status_collection.append(status)
        print "Add {domain} to Route53".format(domain=fqd)    


    for route53_status in status_collection:
        while True:
            if route53_status.update() == "INSYNC":
                print("Domain is INSYNC, bye bye bye!")
                break
            sleep(0.1)

def delete_txt_record(domains):
    domain_dict = parse_domains(domains)
    conn = route53_connect()
    for fqd, token in domain_dict.iteritems():
        zone_name = get_zone_name(fqd)
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

def check_txt_record(fqd):
    zone_name = get_zone_name(fqd)
    conn = route53_connect()
    zone = conn.get_zone(zone_name)
    status = zone.find_records("_acme-challenge." + fqd, "TXT")

    print "Checking {domain}".format(domain=fqd)    

    while True:
        print status
        if status.update() == "INSYNC":
            print "In Sync"
            break
        sleep(0.1)


def parse_and_run(argv):
    fqd = None
    domain_file = None
    try:
        opts, args = getopt.getopt(argv,"ha:d:f:t:l:")
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
        elif opt in ("-l"):
            domain_list = arg
        elif opt in ("-f"):
            domain_file = arg
        elif opt in ("-t"):
            token = arg

    if not fqd and not domain_file and not domain_list:
        print help_text
        sys.exit(0)
    if not action:
        print help_text
        sys.exit(0)

    if action == 'create':
        create_txt_record(domain_list)
    elif action == 'delete': 
        delete_txt_record(domain_list)
    elif action == 'update': 
        update_txt_record(fqd, token)
    elif action == 'check': 
        check_txt_record(fqd)
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
