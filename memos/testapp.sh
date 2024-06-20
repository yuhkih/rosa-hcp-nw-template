oc new-project test-app
oc new-app --name test --image=quay.io/yuhkih0/hello-openshift -l app=test
oc create route edge --service test