#!/usr/bin/env bash 
set -x
export ANSIBLE_STDOUT_CALLBACK=debug

pushd /tmp
rm -Rf quickstart
aws s3 sync s3://{{{QSS3BucketName}}}/{{{QSS3KeyPrefix}}} quickstart/ 

pushd quickstart/playbooks

  # copy parameters into ansible variable file
cat > "vars.yml"<<-EOF
SASSoftwareDepot: "{{{SASSoftwareDepot}}}"
SASSoftwareDepotName: "{{{SASSoftwareDepotName}}}"
SASPlanFiles: "{{{SASPlanFiles}}}"
SASLicenseMeta: "{{{SASLicenseMeta}}}"
SASLicenseApp: "{{{SASLicenseApp}}}"
SASGridKeyPairName: "{{{SASGridKeyPairName}}}"
LustreKeyPairName: "{{{LustreKeyPairName}}}"
LustreOSSEBSVolumeSize: "{{{LustreOSSEBSVolumeSize}}}"
NumberOfOSSNodes: "{{{NumberOfOSSNodes}}}"
DomainDNSName: "{{{DomainDNSName}}}"
VPCID: "{{{VPCID}}}"
VPCCIDR: "{{{VPCCIDR}}}"
PrivateSubnet1ID: "{{{PrivateSubnet1ID}}}"
PrivateSubnet2ID: "{{{PrivateSubnet2ID}}}"
PublicSubnet1ID: "{{{PublicSubnet1ID}}}"
RDGWSG: "{{{RDGWSG}}}"
AdminIngressLocation: "{{{AdminIngressLocation}}}"
QSS3BucketName: "{{{QSS3BucketName}}}"
QSS3KeyPrefix: "{{{QSS3KeyPrefix}}}"
AdminPassword: "{{{AdminPassword}}}"
AWSRegion: "{{{AWSRegion}}}"
EOF

  # distribute additional /etc/hosts entries
  ansible-playbook -vv update_hosts.yml

  # create users, set ulimits, create directories
  ansible-playbook -vv prereqs.yml # use triple mustache to avoid url encoding

  # copy depot files to sasgrid /sas
  ansible-playbook -vv copy_files.yml

  # install lsf
  ansible-playbook -vv lsf_install.yml

  # install sas
  ansible-playbook -vvv sas_install_metadata.yml
  ansible-playbook -vvv sas_install_grid1.yml
popd
