#Ruby 2.7.2 

# Create a program using Ruby which will, on a regular (modifiable) basis, 
# pull all content from a defined upstream repo at that point in time and store 
# it in a new local repo with date stamp and repo upstream naming format.  

# You’ll need to support virtual repositories usage and expect to replace any 
# previously existing repo for the same upstream while not deleting that previous repo 
# (we want to archive it, but not resolve from it).

# get repo from oracle enterprise linux 8 free,EPEL, and EPEL-TESTING, 
# clone current version to a virtual repo in artifactory, archive existing virtual repo.


#################################################################################################################
# assumptions on my part, this is running on a linux system of some sort, and that system has systemd
# /tmp is available
# That the artifactory calls work, I don't have artifactory pro I can test with, tried with OSS but had no luck
# My ruby version is available and I can hit a gem repo of some sort, but since it is downloading from oracle it
# probably does.
# I am also assuming this script is non interactive since its on a schedule
#################################################################################################################

#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require 'faraday'


repoBaseUrl = 'https://yum.oracle.com/repo/OracleLinux/OL8/'
# Yum Branch path(repoPath), Branch Name (repoName) also doubles as virtual repo name
repositories = [
    ['developer/EPEL/x86_64/', "EPEL"], 
    ['baseos/latest/x86_64/', 'baseos']
]
$artifactoryUrl = 'http://localhost:8082/artifactory'
$artifactoryUser = 'rpm-service'
$artifactoryApiKey = 'AKCp8hytFZzBcuLKsbDYzbRquB5wo7GqjBSmpLS4ZZfTHhpgo77xJ4o9N1y9vsu9rHp57d5ot'

# Get list of packages from yum.oracle.com based on repo name parse with nokogiri
def getPackageList(repoBaseUrl, repoPath)
    html = Nokogiri::HTML(URI.open(repoBaseUrl + repoPath))

    # parse href tags and output to variable
    trTags = html.xpath("//tr//a")

    # Initialize array to hold data
    packageList = Array.new

    # parse actual urls for the packages
    trTags.each do |url|
        packageList << "#{url[:href]}".split("/")[1]
    end

    # delete the empty repodata entry at [0]
    packageList.delete_at(0)

    return packageList
end


def downloadPackages(repoBaseUrl, repoPath, repoName, packageList)
    # create staging directory
    folderPath = '/tmp/' + repoName +"/" + Date::today.to_s + "/" + repoPath
    yumUrl = repoBaseUrl + repoPath + 'getPackage/'

    if Dir.exists?(folderPath)
        FileUtils.remove_dir(folderPath, force=true)
    end

    FileUtils.mkdir_p folderPath

    # download packages to staging directory return folder name

    for rpm in packageList do 
        open(folderPath + "/" + rpm, 'wb') do |file|
            file << URI.open(yumUrl + rpm).read
        end
    end

    return folderPath
end

def createArtifactoryRepository (repoName)
    artifactoryRepoDefaults = '{
        "rclass" : "local",
        "packageType": "generic",
        "description": "RPM Repository",
        "notes": "Some internal notes",
        "includesPattern": "**/*",
        "excludesPattern": "",
        "repoLayoutRef" : "maven-2-default",
        "debianTrivialLayout" : false,
        "checksumPolicyType": "client-checksums"
        "handleReleases": true,
        "handleSnapshots": true,
        "maxUniqueSnapshots": 0,
        "maxUniqueTags": 0,
        "snapshotVersionBehavior": "non-unique",
        "suppressPomConsistencyChecks": false,
        "blackedOut": false,
        "xrayIndex" : false,
        "propertySets": ["ps1", "ps2"],
        "archiveBrowsingEnabled" : false,
        "calculateYumMetadata" : false,
        "yumRootDepth" : 0,
        "dockerApiVersion" : "V2",
        "enableFileListsIndexing" : "false",
        "optionalIndexCompressionFormats" : ["bz2", "lzma", "xz"],
        "downloadRedirect" : "false",
        "cdnRedirect": "false",
        "blockPushingSchema1": "false",
        "keyPairRef": "pairName"
    }'

    artifactoryRepoName = repoName +"-" + Date::today.to_s
    apiUrl = $artifactoryUrl + '/api/repositories/' + repoName
    user = $artifactoryUser
    pass = $artifactoryApiKey
    conn = Faraday.new(
        url: apiUrl
    ) 
    conn.basic_auth(user, pass)
    resp = conn.put(apiUrl, artifactoryRepoDefaults)
    puts resp.status
    puts resp.body

    return artifactoryRepoName
end

def uploadPackagesToArtifactory (repoPath, artifactoryRepoName, folderPath, packageList)
    apiUrl = $artifactoryUrl
    repoUrl = "/" + artifactoryRepoName + "/" + repoPath + "/"
    conn = Faraday.new(
        url: apiUrl
        request: multipart
        request: url_encode
        adapter: net_http
    ) 
    
    for rpm in packageList do
        conn.put(repoUrl + rpm) do |req|
            req.body = File.binread(folderPath + rpm)
        end
    end

end

def swapRepos(artifactoryRepoName, repoName)
    artifactoryVirtualRepositoryDefault ='{
        "rclass" : "virtual",
        "packageType": "generic"
        "repositories": ["'+ artifactoryRepoName +'"]
        "description": "The virtual repository public description",
        "notes": "Some internal notes",
        "includesPattern": "**/*" (default),
        "excludesPattern": "" (default),
        "repoLayoutRef" : "maven-2-default",
        "debianTrivialLayout" : false,
        "artifactoryRequestsCanRetrieveRemoteArtifacts": false,
        "keyPair": "keypair1",
        "pomRepositoryReferencesCleanupPolicy": "discard_active_reference",
        "defaultDeploymentRepo": "local-repo1",
        "keyPairRef": "pairName"
    }'

    apiUrl = $artifactoryUrl
    user = $artifactoryUser
    pass = $artifactoryApiKey
    conn = Faraday.new(
        url: apiUrl
    ) 
    conn.basic_auth(user, pass)
    resp = conn.put('/api/repositories/' + repoName, artifactoryVirtualRepositoryDefault)
    puts resp.status
    puts resp.body

end

def cleanUpLocalCache(folderPath)
    # delete local copies
    FileUtils.remove_dir(folderPath, force=true)

end

for repo in repositories do
    packages = getPackageList repoBaseUrl, repo[0]
    folderPath = downloadPackages repoBaseUrl, repo[0], repo[1], packages
    artifactoryRepoName = createArtifactoryRepository repo[1]
    uploadPackagesToArtifactory repo[0], artifactoryRepoName, folderPath, packages
    swapRepos artifactoryRepoName, repo[1]
    cleanUpLocalCache folderPath
end
