#!/usr/bin/env bash

set -e
set -x

#
# update /etc/hosts and the ansible inventory.ini
#
# we retrieve the IPs from from the cloudformation stack and the ec2 metadata
# and with that information compose the lines to add/insert into /etc/hosts and inventory.ini
#

TMPHOSTSFILE=/tmp/extra_hosts
> $TMPHOSTSFILE

TMPANSIBLEHEADER=/tmp/ansible_hosts
> $TMPANSIBLEHEADER

INVENTORYBODY=/tmp/inventory.body # the skeleton is static in the project

# create backup of original hosts file
if ! [ -e /etc/hosts.orig ]
then
  sudo cp /etc/hosts /etc/hosts.orig
fi

# get parent stack
PARENT_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "{{CloudFormationStack}}" --query 'Stacks[].ParentId' --output text)
PARENT_STACK_NAME=$(aws --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "$PARENT_STACK" --query 'Stacks[].StackName' --output text)

#
# Storage substack
#
# If LUSTRE_STACK_ID is not empty, then we have a deployment using Lustre.  Otherwise we should have a deployment using GPFS.
STORAGE_STACK_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK_NAME" --logical-resource-id "LustreStack" --query 'StackResources[*].PhysicalResourceId' --output text)
GRID_STACK_NAME="SASGridStack"
if [ -z "$STORAGE_STACK_ID" ]
then
    STORAGE_STACK_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK_NAME" --logical-resource-id "GPFSStack" --query 'StackResources[*].PhysicalResourceId' --output text)
    GRID_STACK_NAME="GPFSSASGrid"
fi

# wait for storage substack to be complete
STATUS='status'
until [ 1 == "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "$STORAGE_STACK_ID"  --query Stacks[*].StackStatus --output text)
  if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
done

if [ "$GRID_STACK_NAME" == "SASGridStack" ]
then
  # MGTNode
  MGTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MGTNode`].PhysicalResourceId' --output text)
  MGTNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$MGTNode_ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)
  echo "${MGTNode_IP} mgtnode1 mgtnode1.{{DomainDNSName}}" >> $TMPHOSTSFILE
  echo "mgtnode1 ansible_host=${MGTNode_IP}" >> $TMPANSIBLEHEADER
  #sed -i "/^\[mgtnode\]/a mgtnode1" $INVENTORYBODY

  # MDTNode
  MDTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MDTNode`].PhysicalResourceId' --output text)
  MDTNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$MDTNode_ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)
  echo "${MDTNode_IP} mdtnode1 mdtnode1.{{DomainDNSName}}" >> $TMPHOSTSFILE
  echo "mdtnode1 ansible_host=${MDTNode_IP}" >> $TMPANSIBLEHEADER
  #sed -i "/^\[mdtnode\]/a mdtnode1" $INVENTORYBODY

  # OSS Nodes
  OSS_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?LogicalResourceId == `OSSEC2Instances`].PhysicalResourceId' --output text)
  # this value has the oss VM ids separated by ":". Convert it into an array
  IFS=':' read -r -a array <<< "$OSS_IDs"
  for id in "${array[@]}"
  do
    OSSNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$id" --query Reservations[*].Instances[*].PrivateIpAddress --output text)
    OSSNode_Name=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$id" --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --output text)
    OSSNode_Name_Only="$(echo ${OSSNode_Name} | cut -f1 -d '.')"
    echo "$OSSNode_IP $OSSNode_Name_Only $OSSNode_Name" >> $TMPHOSTSFILE
    echo "$OSSNode_Name_Only ansible_host=${OSSNode_IP}" >> $TMPANSIBLEHEADER
    #sed -i "/^\[ossnode\]/a $OSSNode_Name_Only" $INVENTORYBODY
  done
elif [ "$GRID_STACK_NAME" == "GPFSSASGrid" ]
then
  # Compute Node
  Compute_ID=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-security-groups | grep ComputeSecurityGroup- | cut -d'"' -f4 --output text)
  Compute_IP=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-instances --filters "Name=instance.group-name,Values=$Compute_ID" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
  echo "${Compute_IP} gpfscompute1 gpfscompute1.{{DomainDNSName}}" >> $TMPHOSTSFILE
  echo "gpfscompute1 ansible_host=${Compute_IP}" >> $TMPANSIBLEHEADER
  #sed -i "/^\[gpfscompute\]/a gpfscompute1" $INVENTORYBODY

  # Server Nodes
  Server_SG=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-security-groups | grep ServerSecurityGroup- | cut -d'"' -f4 --output text)
  Server_IPs=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-instances --filters "Name=instance.group-name,Values=$Server_SG" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
  count=0
  declare -a array=($Server_IPs)
  for id in "${array[@]}"; do
    count=$((count+1))
    echo "$id gpfsserver$count gpfsserver$count.{{DomainDNSName}}" >> $TMPHOSTSFILE
    echo "gpfsserver$count ansible_host=$id" >> $TMPANSIBLEHEADER
    #sed -i "/^\[gpfsserver\]/a gpfsserver.$count" $INVENTORYBODY
  done
fi

#
# SAS Grid substack
#

# wait for sasgrid substack to be begin creation
SAS_STACK=
until [ -n "$SAS_STACK" ]; do
  sleep 10
  SAS_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK" --logical-resource-id "$GRID_STACK_NAME"  --query StackResources[*].PhysicalResourceId --output text)
done
# wait for sasgrid substack to be be complete
STATUS='status'
until [ 1 == "$(echo "$STATUS" | grep "CREATE_COMPLETE" | wc -w)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "$SAS_STACK"  --query Stacks[*].StackStatus --output text)
  if [ "$(echo "$STATUS" | grep "CREATE_FAILED")" ]; then exit 1; fi
done

# Metadata vm
MetadataNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMetadata`].PhysicalResourceId' --output text)
MetadataNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$MetadataNode_ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)
echo "${MetadataNode_IP} sasgridmeta1 sasgridmeta1.{{DomainDNSName}}" >> $TMPHOSTSFILE
echo "sasgridmeta1 ansible_host=${MetadataNode_IP}" >> $TMPANSIBLEHEADER
#sed -i "/^\[sasgridmeta\]/a sasgridmeta1" $INVENTORYBODY

# Midtier VM
MidtierNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMidTier`].PhysicalResourceId' --output text)
MidtierNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$MidtierNode_ID" --query Reservations[*].Instances[*].PrivateIpAddress --output text)
echo "${MidtierNode_IP} sasgridmidtier1 sasgridmidtier1.{{DomainDNSName}}" >> $TMPHOSTSFILE
echo "sasgridmidtier1 ansible_host=${MidtierNode_IP}" >> $TMPANSIBLEHEADER
#sed -i "/^\[sasgridmidtier\]/a sasgridmidtier1" $INVENTORYBODY

# Grid VMs
Grid_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?LogicalResourceId == `SASGridEC2Instances`].PhysicalResourceId' --output text)
# this value has the oss VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$Grid_IDs"

# loop over the VMs
for id in "${array[@]}"
do

  GridNode_IP=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$id" --query Reservations[*].Instances[*].PrivateIpAddress --output text)

  # The Name tag value is currently <node>.<DomainDNSName> (eg. sasgrid1.example.com), put there by the cloud init code
  # we use that to get the correct node name for the numbered nodes
  GridNode_Name=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-id "$id" --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --output text)
  NameOnly=${GridNode_Name%.{{DomainDNSName}}} # name minus the DomainDNSName

  echo "$GridNode_IP $NameOnly $GridNode_Name" >> $TMPHOSTSFILE
  echo "$NameOnly ansible_host=${GridNode_IP}" >> $TMPANSIBLEHEADER
  #sed -i "/^\[sasgridnodes\]/a $NameOnly" $INVENTORYBODY

done

# update /etc/hosts and inventory.ini
cat /etc/hosts.orig $TMPHOSTSFILE  | sudo tee /etc/hosts
cat $TMPANSIBLEHEADER $INVENTORYBODY > /tmp/inventory.ini

# update lsf config file with gridhostsN-1
SECONDARY_GRIDNODES=$(cat /etc/hosts | cut -d' ' -f3 | grep sasgrid[0-9] | sort | tail -n +2 | xargs)
sed -i "s/SECONDARY_GRIDNODES/${SECONDARY_GRIDNODES}/" /tmp/lsf_install.config
