#!/usr/bin/env python
#Automates the certificate renewal process for Netscaler via REST API and letsencrypt.sh (https://github.com/lukas2511/letsencrypt.sh)
#USE AT OWN RISK

#Imports
import json, requests, base64, os, datetime
#imports variables used for script
from mynsconfig import *

__author__ = "Ryan Butler (techdrabble.com)"
__license__ = "GPL"
__version__ = "1.0.0"
__maintainer__ = "Ryan Butler"

def getAuthCookie(nitroNSIP,nitroUser,nitroPass):
   url = 'http://%s/nitro/v1/config/login' % nitroNSIP
   headers = {'Content-type': 'application/vnd.com.citrix.netscaler.login+json'}
   json_string = {
       "login":{
       "username":nitroUser,
       "password":nitroPass,
       }
   }
   payload = json.dumps(json_string)
   response = requests.post(url, data=payload, headers=headers)
   cookie = response.cookies['NITRO_AUTH_TOKEN']
   nitroCookie = 'NITRO_AUTH_TOKEN=%s' % cookie
   return nitroCookie

def logOut(nitroNSIP,authToken):
   url = 'http://%s/nitro/v1/config/logout' % nitroNSIP
   headers = {'Content-type': 'application/vnd.com.citrix.netscaler.logout+json','Cookie': authToken}
   json_string = {
       "logout":{}
   }
   payload = json.dumps(json_string)
   response = requests.post(url, data=payload, headers=headers)
   print "LOGOUT: %s" % response.reason
   
def SaveNSConfig(nitroNSIP,authToken):
   url = 'http://%s/nitro/v1/config/nsconfig?action=save' % nitroNSIP
   headers = {'Content-type': 'application/json','Cookie': authToken}
   json_string = {
       "nsconfig":{}
   }
   payload = json.dumps(json_string)
   response = requests.post(url, data=payload, headers=headers)
   print "SAVE NS: %s" % response.reason

def sendFile(nitroNSIP,authToken,lecert,nscert,localcertpath,nscertpath):
   url = 'http://%s/nitro/v1/config/systemfile' % nitroNSIP
   headers = {'Content-type': 'application/vnd.com.citrix.netscaler.systemfile+json','Cookie': authToken}
   localcert = localcertpath + lecert
   f = open(localcert, 'r')
   filecontent = base64.b64encode(f.read())
   json_string = {
   "systemfile": {
       "filename": nscert,
       "filelocation": nscertpath,
       "filecontent":filecontent,
       "fileencoding": "BASE64",}
   }
   payload = json.dumps(json_string)
   response = requests.post(url, data=payload, headers=headers)
   print "CREATE CERT: %s" % response.reason

def removeFile(nitroNSIP,authToken,nscert,nscertpath):
   url = 'http://%s/nitro/v1/config/systemfile/%s?args=filelocation:%%2Fnsconfig%%2Fssl' % (nitroNSIP, nscert)
   headers = {'Content-type': 'application/vnd.com.citrix.netscaler.systemfile+json','Cookie': authToken}
   response = requests.delete(url, headers=headers)
   print "DELETE NETSCALER CERTIFICATE: %s" % response.reason
   return response

def getNSFileDate(nitroNSIP,authToken,nscert):
   url = 'http://%s/nitro/v1/config/systemfile/%s?args=filelocation:%%2Fnsconfig%%2Fssl' % (nitroNSIP, nscert)
   headers = {'Content-type': 'application/vnd.com.citrix.netscaler.systemfile+json','Cookie': authToken}
   response = requests.get(url, headers=headers)
   response = json.loads(response.text)
   response = response['systemfile'][0]['filemodifiedtime']
   print response
   return response

def updateSSL(nitroNSIP,authToken, nscert, nspairname):
   url = 'http://%s/nitro/v1/config/sslcertkey?action=update' % nitroNSIP
   headers = {'Content-type': 'application/json','Cookie': authToken}
   json_string = {
   "sslcertkey": {
       "certkey": nspairname,
       "cert": nscert,}
   }
   payload = json.dumps(json_string)
   response = requests.post(url, data=payload, headers=headers)
   print "Update Netscaler CERT: %s" % response.reason

def modification_date(filename):
    t = os.path.getmtime(filename)
    return datetime.datetime.fromtimestamp(t)


#Verify cert has been updated by Letsencrypt.sh before run
date =  datetime.datetime.now()
localcert = localcertpath + lecert
filedate = modification_date(localcert)
tdelta = date - filedate

if tdelta.days == 0:
   print "Updating Netscaler Certificate"
   authToken = getAuthCookie(nitroNSIP,nitroUser,nitroPass)
   removeFile(nitroNSIP,authToken,nscert,nscertpath)
   sendFile(nitroNSIP,authToken,lecert,nscert,localcertpath,nscertpath)
   updateSSL(nitroNSIP,authToken, nscert, nspairname)
   SaveNSConfig(nitroNSIP,authToken)
   logOut(nitroNSIP,authToken)