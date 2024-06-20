## Prerequisites

* A multi-region ROSA cluster with STS enabled
* AWS CLI
* Helm 3 CLI
* rosa CLI
* 3 AZ

https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller
https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/?nc1=h_ls


## Getting Started

1. Login OpenShift 

    ```
    oc login https://api.my-cluster.m51o.p1.openshiftapps.com:6443 --username cluster-admin --password CoSIw-jxpVD-UGsNz-xypAM
    ```

1. configure AWS CLI

    ```
    aws configure
    ```

1. Set some environment variables

    ```bash
    export AWS_PAGER=""
    export ALB_VERSION="v2.4.0"
    export CLUSTER_NAME="my-cluster"
    export SCRATCH_DIR="/tmp/alb-sts"
    export OIDC_PROVIDER=$(oc get authentication.config.openshift.io cluster -o json \
      | jq -r .spec.serviceAccountIssuer| sed -e "s/^https:\/\///")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export REGION=$(rosa describe cluster -c $CLUSTER_NAME -o json | jq -r .region.id)
    # export REGION=ap-northeast-1
    export NAMESPACE="alb-controller"
    export SA="alb-controller"
    rm -rf $SCRATCH_DIR
    mkdir -p $SCRATCH_DIR
    ```

## Configure IAM credentials

1. Create AWS Policy and Service Account

    ```bash
    wget -O $SCRATCH_DIR/iam-policy.json \
      https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/$ALB_VERSION/docs/install/iam_policy.json

    POLICY_ARN=$(aws iam create-policy --policy-name  \
      "AWSLoadBalancerControllerIAMPolicy-$ALB_VERSION" \
      --policy-document file://$SCRATCH_DIR/iam-policy.json \
      --query Policy.Arn --output text)

    echo $POLICY_ARN
    ```

    If the Policy already exists you can use this instead

    ```bash
    POLICY_ARN=$(aws iam list-policies \
      --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy-'$ALB_VERSION'`].Arn' \
      --output text)

    echo $POLICY_ARN
    ```

1. Create a Trust Policy

    ```bash
    cat <<EOF > $SCRATCH_DIR/TrustPolicy.json
    {
     "Version": "2012-10-17",
     "Statement": [
         {
         "Effect": "Allow",
         "Principal": {
             "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
             "StringEquals": {
             "${OIDC_PROVIDER}:sub": [
                 "system:serviceaccount:${NAMESPACE}:${SA}"
             ]
             }
         }
         }
     ]
     }
    EOF
    ```

1. Create Role for ALB Controller

    ```bash
    ALB_ROLE=$(aws iam create-role \
      --role-name "$CLUSTER_NAME-alb-controller" \
      --assume-role-policy-document file://$SCRATCH_DIR/TrustPolicy.json \
      --query "Role.Arn" --output text)
    echo $ALB_ROLE
    ```

1. Attach the Policies to the Role

    ```bash
    aws iam attach-role-policy \
      --role-name "$CLUSTER_NAME-alb-controller" \
      --policy-arn $POLICY_ARN
    ```

## Configure Cluster subnets

1. Get the Instance Name of one of your worker nodes

    ```bash
    NODE=$(oc get nodes --selector=node-role.kubernetes.io/worker \
    -o jsonpath='{.items[0].metadata.name}')
    echo $NODE
    ```

1. Get the VPC ID of your worker nodes

    ```bash
    VPC=$(aws ec2 describe-instances \
    --filters "Name=private-dns-name,Values=$NODE" \
    --query 'Reservations[*].Instances[*].{VpcId:VpcId}' \
    | jq -r '.[0][0].VpcId')
    echo $VPC
    ```

1. Get list of Subnets

    If ROSA Public cluster

    ```bash
    SUBNET_IDS=$(aws ec2 describe-subnets --output json \
      --filters Name=tag-value,Values="${CLUSTER_NAME}-*public*" \
      --query "Subnets[].SubnetId" --output text | sed 's/\t/ /g')
    echo ${SUBNET_IDS}
    ```

    If ROSA Private Cluster (you need three subnet IDs with space separation)

    ```
    SUBNET_IDS= <set your public subnet ids in the ROSA cluster VPC with space>
    ````



1. Add tags to those subnets (change the subnet ids in the resources line)

    ```bash
    aws ec2 create-tags \
      --resources $(echo ${SUBNET_IDS}) \
       --tags Key=kubernetes.io/role/elb,Value='1' Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared
    ```

1. Create a namespace for the controller

    ```bash
    oc new-project $NAMESPACE
    ```

1. Apply CRDs

    ```bash
    kubectl apply -k \
      "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
    ```

1. Add the helm repo and install the controller (install [helm3](https://github.com/helm/helm/releases/tag/v3.5.4) if not already)

    ```bash
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    helm upgrade alb-controller eks/aws-load-balancer-controller -i \
      -n $NAMESPACE \
      --set clusterName=$CLUSTER_NAME \
      --set serviceAccount.name=$SA \
      --set "vpcId=$VPC" \
      --set "region=$REGION" \
      --set serviceAccount.annotations.'eks\.amazonaws\.com/role-arn'=$ALB_ROLE \
      --set "image.repository=amazon/aws-alb-ingress-controller" \
      --set "image.tag=$ALB_VERSION" --version 1.4.0 
    ```

1. Update SCC to allow setting fsgroup in Deployment

    ```bash
    oc adm policy add-scc-to-user anyuid -z $SA -n $NAMESPACE
    ```

### Deploy Sample Application

1. Create a new application in OpenShift

    ```bash
    oc new-project demo
    oc new-app https://github.com/sclorg/django-ex.git
    kubectl -n demo patch service django-ex -p '{"spec":{"type":"NodePort"}}'
    ```

1. Create an Ingress to trigger an ALB

    > Note: Setting the `alb.ingress.kubernetes.io/group.name` allows you to create multiple ALB Ingresses using the same ALB which can help reduce your AWS costs
    > Note: alb.ingress.kubernetes.io/scheme: internet-facing or internal
    
    https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/guide/ingress/annotations/


    ```bash
    cat << EOF | kubectl apply -f -
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
    name: django-ex
    namespace: demo
    annotations:
        kubernetes.io/ingress.class: alb
        alb.ingress.kubernetes.io/scheme: internet-facing
        alb.ingress.kubernetes.io/target-type: instance
        alb.ingress.kubernetes.io/group.name: "demo"
    labels:
        app: django-ex
    spec:
        rules:
        - host: foo.bar
        http:
            paths:
            - pathType: Prefix
            path: /
            backend:
                service:
                name: django-ex
                port:
                    number: 8080
    EOF
    ```

1. Check the logs of the ALB controller

    ```bash
    kubectl -n $NAMESPACE logs -f \
       deployment/alb-controller-aws-load-balancer-controller 
    ```

1. Save the ingress address

    ```bash
    URL=$(kubectl -n demo get ingress django-ex \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    ```

    ```bash
    curl -s --header "Host: foo.bar" $URL | head
    ```

    ```html
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
      <title>Welcome to OpenShift</title>
    ```

## Cleanup

1. Delete the demo app

    ```bash
    kubectl delete ns demo
    ```

1. Uninstall the ALB Controller

    ```bash
    helm delete -n $NAMESPACE alb-controller
    ```

1. Get PolicyARN

    ```bash
    POLICY_ARN=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy-'$ALB_VERSION'`].Arn' \
    --output text)
    ```

1. Dettach the Policy from the Role

    ```bash
    aws iam detach-role-policy \
      --role-name "$CLUSTER_NAME-alb-controller" \
      --policy-arn $POLICY_ARN
    ```

1. Delete Role for ALB Controller

    ```bash
    aws iam delete-role \
      --role-name "$CLUSTER_NAME-alb-controller"
    ```