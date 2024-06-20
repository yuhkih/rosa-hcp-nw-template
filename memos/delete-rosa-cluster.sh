#!/bin/sh
# 2023/01/20 yuhkih initial make

# ClusterName=my-cluster
# ClusterName=nonstspub
ClusterName=rosa-cluster


# need to get cluster id before deleting the cluster
echo "[Log] get cluster id" 
CLUSTER_ID=$(rosa list cluster | grep $ClusterName | awk -F' ' '{print $1}')
echo "[Log] cluster id is $CLUSTER_ID"

# delete cluster
echo "[Log] cluster name is " $ClusterName 
rosa delete cluster -y -c $ClusterName
rosa logs uninstall -c $ClusterName --watch

# The followings didn't work. need to specify ID like 219fial09eqna3rdl1pi9ss0qmi8blu2
echo "[Log] delete operator-roles"
rosa delete operator-roles -y -m auto -c $CLUSTER_ID 
echo "[Log] delete oidc-provider"
rosa delete oidc-provider  -y -m auto -c $CLUSTER_ID
