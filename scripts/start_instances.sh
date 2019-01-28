#!/usr/bin/env bash

set -e
set -x

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

if [ "$GRID_STACK_NAME" == "SASGridStack" ]
then
    # MGTNode
    MGTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MGTNode`].PhysicalResourceId' --output text)
    aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MGTNode_ID

    # MDTNode
    MDTNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `MDTNode`].PhysicalResourceId' --output text)

    # StartMDTNode and MGTNode
    aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MGTNode_ID $MDTNode_ID

    # Check status of MDTNode and MGTNode
    STATUS='status'
    until [ 2 == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
      sleep 10
      STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $MGTNode_ID $MDTNode_ID --query InstanceStatuses[*].SystemStatus --output text)
    done

    # OSS Nodes
    OSS_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $STORAGE_STACK_ID  --query 'StackResources[?LogicalResourceId == `OSSEC2Instances`].PhysicalResourceId' --output text)
    if [ -f /tmp/oss_nodes ]; then
      rm /tmp/oss_nodes
    fi
    
    # this value has the oss VM ids separated by ":". Convert it into an array
    IFS=':' read -r -a array <<< "$OSS_IDs"
    for id in "${array[@]}"
    do
      echo "$id" >> /tmp/oss_nodes
    done

    # Start oss nodes
    o_ids=$(cat /tmp/oss_nodes)
    o_ct=$(cat /tmp/oss_nodes | wc -w)
    aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $o_ids

    # Check status of ossnodes
    STATUS='status'
    STATUS_CHECK_STOPPED='status'
    until [ $o_ct == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
      sleep 10
      STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $o_ids --query InstanceStatuses[*].SystemStatus --output text)
      STATUS_CHECK_STOPPED=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-ids $o_ids --query Reservations[*].Instances[*].State --output text)
      if [[ $(echo "$STATUS_CHECK_STOPPED" | grep -o "stopped" | wc -l) > 0 ]]; then aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $o_ids; fi
    done
elif [ "$GRID_STACK_NAME" == "GPFSSASGrid" ]
then
    # GPFS Compute Node
    Compute_SG=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-security-groups | grep ComputeSecurityGroup- | cut -d'"' -f4 --output text)
    Compute_ID=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-instances --filters "Name=instance.group-name,Values=$Compute_SG" --query 'Reservations[*].Instances[*].InstanceId[]' --output text)

    aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $Compute_ID

    # Check status of Compute GPFS Node  
    STATUS='status'
    until [ 1 == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
      sleep 10
      STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $Compute_ID --query InstanceStatuses[*].SystemStatus --output text)
    done

    # GPFS Server Nodes
    Server_SG=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-security-groups | grep ServerSecurityGroup- | cut -d'"' -f4 --output text)
    Server_IPs=$(aws --no-paginate ec2 --region "{{AWSRegion}}" describe-instances --filters "Name=instance.group-name,Values=$Server_SG" --query 'Reservations[*].Instances[*].InstanceId[]' --output text)
    if [ -f /tmp/server_nodes ]; then
      rm /tmp/server_nodes
    fi
    
    # this value has the oss VM ids separated by ":". Convert it into an array
    count=0
    declare -a array=($Server_IPs)
    for id in "${array[@]}"; do
      count=$((count+1))
      echo "$id" >> /tmp/server_nodes
    done

    # Start GPFS Server Nodes
    g_ids=$(cat /tmp/server_nodes)
    g_ct=$(cat /tmp/server_nodes | wc -w)
    aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $g_ids

    # Check status of GPFS Server Nodes
    STATUS='status'
    STATUS_CHECK_STOPPED='status'
    until [ $g_ct == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
      sleep 10
      STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $g_ids --query InstanceStatuses[*].SystemStatus --output text)
      STATUS_CHECK_STOPPED=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-ids $g_ids --query Reservations[*].Instances[*].State --output text)
      if [[ $(echo "$STATUS_CHECK_STOPPED" | grep -o "stopped" | wc -l) > 0 ]]; then aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $g_ids; fi
    done
fi

# SAS Grid substack
SAS_STACK=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name "$PARENT_STACK" --logical-resource-id "$GRID_STACK_NAME"  --query StackResources[*].PhysicalResourceId --output text)

# Metadata VM
MetadataNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMetadata`].PhysicalResourceId' --output text)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MetadataNode_ID

# Midtier VM
MidtierNode_ID=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?ResourceType ==`AWS::EC2::Instance`]|[?LogicalResourceId == `SASGridMidTier`].PhysicalResourceId' --output text)
echo "$MidtierNode_ID" >> /tmp/sas_nodes
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $MidtierNode_ID

# Check status of midtier and metadata nodes
STATUS='status'
until [ 2 == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $MetadataNode_ID $MidtierNode_ID --query InstanceStatuses[*].SystemStatus --output text)
done

# Grid VMs
Grid_IDs=$(aws --no-paginate --region "{{AWSRegion}}" cloudformation describe-stack-resources --stack-name $SAS_STACK  --query 'StackResources[?LogicalResourceId == `SASGridEC2Instances`].PhysicalResourceId' --output text)

if [ -f /tmp/sas_nodes ]; then
  rm /tmp/sas_nodes
fi

# this value has the grid VM ids separated by ":". Convert it into an array
IFS=':' read -r -a array <<< "$Grid_IDs"
for id in "${array[@]}"
do
  echo "$id" >> /tmp/sas_nodes
done

# Start sas nodes
s_ids=$(cat /tmp/sas_nodes)
s_ct=$(cat /tmp/sas_nodes | wc -l)
aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $s_ids

# Check status of sas nodes
STATUS='status'
STATUS_CHECK_STOPPED='status'
until [ $s_ct == "$(echo "$STATUS" | grep -o "passed" | wc -l)" ]; do
  sleep 10
  STATUS=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instance-status --instance-ids $s_ids --query InstanceStatuses[*].SystemStatus --output text)
  STATUS_CHECK_STOPPED=$(aws --no-paginate --region "{{AWSRegion}}" ec2 describe-instances --instance-ids $s_ids --query Reservations[*].Instances[*].State --output text)
  if [[ $(echo "$STATUS_CHECK_STOPPED" | grep -o "stopped" | wc -l) > 0 ]]; then aws ec2 --region "{{AWSRegion}}" start-instances --instance-ids $s_ids; fi
done

ansible-playbook lsf_restart.yml -vv
ansible-playbook sas_servers_start.yml -vv
