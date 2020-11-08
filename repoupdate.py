#Python 3.7

# Create a second script in python that would check an upstream repo (EPEL use case) 
# for newer content and versions and download them to a local repo.  
# This should result in keeping multiple versions of the same package in the local 
# repo where the upstream only maintains latest.

# Since I dont have access to artifactory pro I used this json block as my test mule after i fixed it to be valid json
# https://www.jfrog.com/confluence/display/JFROG/Artifactory+REST+API#ArtifactoryRESTAPI-FileList

#! /usr/bin/env python

import requests
import os
import sys
from bs4 import BeautifulSoup
import json
from datetime import date

print("Set python variables")
artifactoryUser = os.environ['ART_USER']
artifactoryToken = os.environ['ART_TOKEN']
artifactoryRepoName = 'epel'
artifactoryAPIUrl = 'http://localhost:8082/artifactory/'
artifactoryRepoUrl = artifactoryAPIUrl + 'api/storage/' + artifactoryRepoName
artifactoryUploadUrl = artifactoryAPIUrl + artifactoryRepoName + "/"
yumEpelUrl = 'https://yum.oracle.com/repo/OracleLinux/OL8/developer/EPEL/x86_64/'
yumDownloadUrl = yumEpelUrl + 'getPackage/'

print("Pull list of packaged from artifactory")
artOut = requests.get('artifactoryRepoUrl', auth=(artifactoryUser, artifactoryToken))

print(artOut.status_code)

if artOut.status_code == 200:
    artJsonResponse = artOut.json()
else:
    print("Artifactory connection error:", artOut.status_code)
    artOut.raise_for_status()
    sys.exit(1)

print('Convert json output to dictionary for parsing')
json_dict = json.loads(artJsonResponse)
files = json_dict['files'] 
artRpms = []

for item in files:
    artRpms.append(item.get('uri').split("/")[1])

print("Pull list of packaged from oracle yum epel")
yumOut = requests.get(yumEpelUrl)

if yumOut.status_code == 200:
    yumResponse = yumOut.text
else:
    print("Error connecting to oracle yum repo:", yumOut.status_code)
    yumOut.raise_for_status()
    sys.exit(1)

print('Creating list of rpms from yum repo')
soup = BeautifulSoup(yumResponse, 'html.parser')

yumRpms = []

for link in soup.find_all('a'):
    if 'getPackage' in link.get('href'):
        rpm = link.get('href').split("/")[1]
        yumRpms.append(rpm)


diffRpms = []
print('Create a list of the rpms not in artifactory')
for i in yumRpms:
    if i not in artRpms:
        diffRpms.append(i)

print('Downloading missing rpms')
tempDir = '/tmp/epel/' + str(date.today())
os.makedirs(tempDir)

for rpm in diffRpms:
    url = yumDownloadUrl + rpm
    req = requests.get(url)
    with open(tempDir + "/" + rpm, 'wb') as d:
        d.write(req.content)
    if req.status_code != 200:
        req.raise_for_status()
        sys.exit(1)


print('Push objects to artifactory')
for rpm in diffRpms:
    uploadFile = {'file': open(tempDir + "/" + rpm, 'rb')}
    req = requests.put(artifactoryUploadUrl, files=uploadFile)
    if req.status_code != 201:
        req.raise_for_status
        sys.exit(1)

print('Clean up temp directory')
os.removedirs(tempDir)