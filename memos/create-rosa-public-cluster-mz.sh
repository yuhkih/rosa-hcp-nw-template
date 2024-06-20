#!/bin/bash

# Non-STS Public Cluster / BYOPVC
# ------------------------------------------------------
# Make sure aws cli is configured properly before run this shell
# ------------------------------------------------------
# History
# 2023/01/17 yuhkih initial creation based on Multi AZ shell
# 2023/01/20 yuhkih added confirmation (y/n)
# 2023/01/27 yuhkih added --sts (sts is not default yet)
# 2023/01/27 yuhkih created from private version 
# 2023/02/06 yuhkih added --sts (sts is not default yet)
# 2023/02/06 yuhkih added GitHub integration confirmation
# 2023/02/15 yuhkih created based on SZ version.
# 2023/03/07 yuhkih makde some changes to employ BYOVPC. (Not tested yet)


# ------------------------------------------------------
# Basic Information
# ------------------------------------------------------
ClusterName=my-cluster
RosaCIDR="10.0.0.0/16"
NumberOfWorkers="3"  # need to be multiple of 3.
# RosaVersion="4.10.47"
RosaVersion="4.12.4"
Region="ap-northeast-1"
# RosaVersion="4.12"
SubnetTagHeader="nonstspub"

# ------------------------------------------------------
# Get ROSA VPC subnetIds
# ------------------------------------------------------
export PrivateSubnetID1=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Private-Subnet1 | awk -F'[,]' '{print $2}' | sed 's/"//g'`
export PrivateSubnetID2=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Private-Subnet2 | awk -F'[,]' '{print $2}' | sed 's/"//g'`
export PrivateSubnetID3=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Private-Subnet3 | awk -F'[,]' '{print $2}' | sed 's/"//g'`

export PublicSubnetID1=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Public-Subnet1 | awk -F'[,]' '{print $2}' | sed 's/"//g'`
export PublicSubnetID1=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Public-Subnet1 | awk -F'[,]' '{print $2}' | sed 's/"//g'`
export PrublicSubnetID1=`aws ec2 describe-subnets | jq -r '.Subnets[] | [ .CidrBlock, .SubnetId, .AvailabilityZone, .Tags[].Value ] | @csv' | grep "$SubnetTagHeader"-Public-Subnet1 | awk -F'[,]' '{print $2}' | sed 's/"//g'`

# ------------------------------------------------------
# Create IAMRole and set them to variables 
# ------------------------------------------------------
rosa create account-roles -m auto -y

# ------------------------------------------------------
# Get Necessary parameter for CLI installation
# ------------------------------------------------------
INSTALL_ROLE=`aws iam list-roles | jq -r '.Roles[] | [.RoleName, .Arn] | @csv' | grep ManagedOpenShift-Installer-Role |  awk -F'[,]' '{print $2}' | sed 's/"//g'`
SUPPORT_ROLE=`aws iam list-roles | jq -r '.Roles[] | [.RoleName, .Arn] | @csv' | grep ManagedOpenShift-Support-Role |  awk -F'[,]' '{print $2}' | sed 's/"//g'`
CONTROL_PLANE_ROLE=`aws iam list-roles | jq -r '.Roles[] | [.RoleName, .Arn] | @csv' | grep ManagedOpenShift-ControlPlane-Role |  awk -F'[,]' '{print $2}' | sed 's/"//g'`
WORKER_ROLE=`aws iam list-roles | jq -r '.Roles[] | [.RoleName, .Arn] | @csv' | grep ManagedOpenShift-Worker-Role |  awk -F'[,]' '{print $2}' | sed 's/"//g'`


# ---------------------------
#  Check parameters are set before creating cluster
# ---------------------------
echo "=============================================================="
# echo "[log] install parameters"
echo "RosaCIDR = " $RosaCIDR
echo "ClusterName = " $ClusterName
echo "Region = " $Region
echo "PrivateSubnetID1 = " $PrivateSubnetID1
echo "PrivateSubnetID2 = " $PrivateSubnetID2
echo "PrivateSubnetID3 = " $PrivateSubnetID3
echo "PublicSubnetID1 = " $PublicSubnetID1
echo "PublicSubnetID2 = " $PublicSubnetID2
echo "PublicSubnetID3 = " $PublicSubnetID3
# echo "FwSubnetID1 = " $FwSubnetID1
# echo "FwSubnetID2 = " $FwSubnetID2
# echo "FwSubnetID3 = " $FwSubnetID3
echo "INSTALL_ROLE = " $INSTALL_ROLE
echo "SUPPORT_ROLE = "$SUPPORT_ROLE
echo "CONTROL_PLANE_ROLE = " $CONTROL_PLANE_ROLE
echo "WORKER_ROLE = " $WORKER_ROLE
echo "RosaCIDR = " $RosaCIDR
echo "NumberOfWorkers = " $NumberOfWorkers
echo "RosaVersion = " $RosaVersion
echo "=============================================================="

echo "[Log] Last confirmationk"
read -p "Are you ok with above parameters? (y/N): " yn
case "$yn" in [yY]*) ;; *) echo "abort." ; exit ;; esac

# ---------------------------------------
#  Create ROSA cluster (Single AZ)
# ---------------------------------------
echo "=============================================================="
echo "[log] run rosa create cluster"
rosa create cluster --cluster-name $ClusterName --sts \
  --multi-az \
  --role-arn $INSTALL_ROLE \
  --support-role-arn $SUPPORT_ROLE \
  --controlplane-iam-role $CONTROL_PLANE_ROLE \
  --worker-iam-role $WORKER_ROLE \
  --region $Region --version $RosaVersion --compute-nodes $NumberOfWorkers --compute-machine-type m5.xlarge \
  --machine-cidr $RosaCIDR --service-cidr 172.30.0.0/16 --pod-cidr 10.128.0.0/14  --host-prefix 23 \
  --subnet-ids $PrivateSubnetID1, $PublicSubnetID1, $PrivateSubnetID2, $PublicSubnetID2, $PrivateSubnetID3, $PublicSubnetID3 
# ------------------------------------------------
# After "rosa create cluster" 
# create operator roles and OIDC Provider 
# ------------------------------------------------
echo "=============================================================="
echo "[log] create operator roles and oidc provider"
rosa create operator-roles -y -m auto --cluster $ClusterName
rosa create oidc-provider -y -m auto --cluster $ClusterName

# ------------------------------------------------
# Wait until the cuslter becomes ready
# ------------------------------------------------
echo "=============================================================="
echo "[log] monitor installation completion"
rosa logs install -c $ClusterName --watch

# ---------------------------
# Create ROSA admin user
# ---------------------------
# create cluster admin after cluster installation completes
echo "=============================================================="
echo "[log] create admin user"
rosa create admin -c $ClusterName


# ---------------------------
# GitHub IdP integration
# ---------------------------
echo "[Log] GitHub integration confirmation"
read -p "Would you like to integrate with GitHub IdP? (y/N): " yn
case "$yn" in [yY]*) ;; *) echo "[Log] ROSA cluster installation is completed(GitHub integiration Aborted)" ; exit ;; esac
rosa create idp --type=github --cluster=$ClusterName