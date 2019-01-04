#!/usr/bin/env bash

set -e
set -x

ansible-playbook sas_servers_stop.yml -vv

# get parent stack
PARENT_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "{{CloudFormationStack}}" --query 'Stacks[].ParentId' --output text)

# Storage substack
PARENT_STACK_NAME=$(aws --region "{{AWSRegion}}" cloudformation describe-stacks --stack-name "$PARENT_STACK" --query 'Stacks[].StackName' --output text)

STORAGE_STACK_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK_NAME" --logical-resource-id "LustreStack" --query 'StackResources[*].PhysicalResourceId' --output text)
GRID_STACK_NAME="SASGridStack"
if [ -z "$STORAGE_STACK_ID" ]
then
    STORAGE_STACK_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK_NAME" --logical-resource-id "GPFSStack" --query 'StackResources[*].PhysicalResourceId' --output text)
    GRID_STACK_NAME="GPFSSASGrid"
fi

# MGTNode
MGTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MGTNode`].PhysicalResourceId' --output text)
echo "$MGTNode_ID" > /tmp/mylist

# MDTNode
MDTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MDTNode`].PhysicalResourceId' --output text)
echo "$MDTNode_ID" >> /tmp/mylist

# OSS Nodes
OSS_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?LogicalResourceId == `OSSEC2Instances`].PhysicalResourceId' --output text)
# this value has the oss VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$OSS_IDs"
for id in "${array[@]}"
do
  echo "$id" >> /tmp/mylist
done

# SAS Grid substack
SAS_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK" --logical-resource-id "$GRID_STACK_NAME"  --query StackResources[*].PhysicalResourceId --output text)

# Metadata VM
MetadataNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMetadata`].PhysicalResourceId' --output text)
echo "$MetadataNode_ID" >> /tmp/mylist

# Midtier VM
MidtierNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMidTier`].PhysicalResourceId' --output text)
echo "$MidtierNode_ID" >> /tmp/mylist

# Grid VMs
Grid_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?LogicalResourceId == `SASGridEC2Instances`].PhysicalResourceId' --output text)
# this value has the grid VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$Grid_IDs"
for id in "${array[@]}"
do
  echo "$id" >> /tmp/mylist
done

vartemp=$(cat /tmp/mylist)
aws ec2 --region "{{AWSRegion}}" stop-instances --instance-ids $vartemp
