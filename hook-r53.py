#!/usr/bin/env python
import boto3
import json
import sys
import os

if len(sys.argv) < 3: exit

#for i, arg in enumerate(sys.argv):
#    print i, arg

def create_record(domain, token, zoneid):
    conn = boto3.client('route53')
    changeset = '''{"Comment": "Create ACME verification record for TLS cert",
                "Changes": [{"Action": "UPSERT","ResourceRecordSet": {"Name": "_acme-challenge.example.com",
                "Type": "TXT", "TTL": 30, "ResourceRecords": [{"Value": "\"AAAAAAAAAAAAAA\""}]}}]}'''
    #changeset = json.loads(open("record.json", "r").read())
    changeset['Changes'][0]['ResourceRecordSet']['Name'] = "_acme-challenge.{}".format(domain)
    changeset['Changes'][0]['ResourceRecordSet']['ResourceRecords'][0]['Value'] = "\"{}\"".format(token)
    response = conn.change_resource_record_sets(
        HostedZoneId=zoneid,
        ChangeBatch=changeset)
    #print response
    responseid = response['ChangeInfo']['Id']
    #print responseid
    print 'Waiting on DNS record confirmation'
    waiter = conn.get_waiter('resource_record_sets_changed')
    waiter.wait(Id=responseid, delay=5)
    print 'done waiting'
    return response
    
def clean_record(domain, token, zoneid):
    pass

def deploy_cert(domain, token, zoneid):
    iam = boto3.client('iam')
    response = iam.upload_server_certificate(
        ServerCertificateName=domain,
        CertificateBody=open(sys.argv[4]).read(),
        PrivateKey=open(sys.argv[3]).read(),
        CertificateChain=open(sys.argv[5]).read()
    )
    return response

def update_cert(domain, token, zoneid):
    iam = boto3.client('iam')
    response = iam.upload_server_certificate(
        ServerCertificateName=domain+'2',
        CertificateBody=open(sys.argv[4]).read(),
        PrivateKey=open(sys.argv[3]).read(),
        CertificateChain=open(sys.argv[6]).read()
    )
    return response 

if __name__ == "__main__":
    zoneid = os.environ['R53_ZONEID']
    command = sys.argv[1]
    domain = sys.argv[2]
    token = sys.argv[4]
    operations = {'deploy_challenge': create_record,
                  'clean_challenge': clean_record,
                  'deploy_cert': deploy_cert,
                  'update_cert': update_cert}
     
    response = operations[command](domain, token, zoneid)
    print response
