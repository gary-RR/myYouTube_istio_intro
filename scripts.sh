#!/bin/bash

#Download istio
curl -L https://istio.io/downloadIstio | sh -

#Change directory to where the istio downlad is
cd </istio-x.x.x>

PATH=$PWD/bin:$PATH

#Instal Instio "configuration profile"
istioctl install --set profile=demo -y

kubectl get pods -n istio-system

istioctl analyze

#Dashboard
    #Kiali and the other addons 
    kubectl apply -f samples/addons
    #Run this in a different terminal session
        istioctl dashboard kiali

#*************************************Virtual Services, Gateways, Routing Rules, and Load Balancer/ *******************************************************************

export MYSERVICE_V1_POD_NAME;
export MYSERVICE_CLUSTERIP;
export TEST_POD_NAME;
export INGRESS_PORT;
export SECURE_INGRESS_PORT;
export INGRESS_HOST;  
export GATEWAY_URL;
export GATEWAY_CLUSTERIP;

kubectl create namespace myservice
#Enable istio side car label injection for this name space 
kubectl label namespace myservice istio-injection=enabled

#Deploy the test POD and our V1 Service
    #Deploy a test POD to test the service
    kubectl create deployment test -n myservice --image=gcr.io/google-samples/hello-app:1.0
    #Get POD name
    TEST_POD_NAME=$(kubectl get pods -no-headers -n myservice | awk '{ print $1}' | grep test)
    #Install curl on the test POD
    kubectl exec -it $TEST_POD_NAME -n myservice  -- apk --no-cache add curl
    
    #Deploy myservice V1
    kubectl apply -f  ./kube/myservice-v1.yaml -n myservice

    MYSERVICE_V1_POD_NAME=$(kubectl get pods -no-headers -n myservice | awk '{ print $1}' | grep myservice-v1)
    MYSERVICE_CLUSTERIP=$(kubectl get service myservice -n myservice -o jsonpath='{ .spec.clusterIP }')

    #Show the itsio side car
    kubectl get pods $MYSERVICE_V1_POD_NAME -n myservice  -o jsonpath='{.spec.containers[*].name}*'

#Deploy the gateway and virtual service and load balance 80% to 20% 
    #Register the legacy service in istio
    kubectl apply -f ./istio/myservice-legacy-svc-entry.yaml -n myservice
    #Define destination rules
    kubectl apply -f ./istio/myservice-destination-rule.yaml -n myservice
    #Creat the external ingres and the istio virtual service
    kubectl apply -f  ./istio/myservice-gateway-v1-80-20.yaml -n myservice

    #Set the INGRESS_HOST and INGRESS_PORT variables for accessing the gateway
    GATEWAY_CLUSTERIP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.clusterIP}')
    INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
    SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
    INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
    #GATEWAY_URL
    GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT
    #Ensure an IP address and port were successfully assigned to the environment variable
    echo "http://$GATEWAY_URL/computer"

    #Make a change in the load balancer to point it to "$GATEWAY_URL" rather than legacy servers 
    #Run this from an external client to generate some traffic to view in Kiali
        for i in $(seq 1 100); do curl -s -o /dev/null  http://myservice.net/computer; done
    
#Deploy myservice V2 
    kubectl apply -f  ./kube/myservice-v2.yaml -n myservice
     
#Update the gateway bond virtual service to include myservice V2 in a 70-20-10 load distribution  
    kubectl apply -f ./istio/myservice-gateway-v2-70-20-10.yaml -n myservice
    #Run this from an external client to generate some traffic to view in Kiali
     for i in $(seq 1 100); do curl -s -o /dev/null  http://myservice.net/computer; done
   
#Add falut injection, trials, and timeouts
    kubectl apply -f ./istio/myservice-gateway-v3-50-30-20-fault-retry.yaml  -n myservice

#Finally, remove legacy service from load
    kubectl apply -f ./istio/myservice-gateway-v4-0-70-30.yaml -n myservice
    #Run this from an external client to generate some traffic to view in Kiali
    for i in $(seq 1 100); do kubectl exec -it $TEST_POD_NAME -n myservice  --  curl -s -o /dev/null http://$GATEWAY_CLUSTERIP/computer; done
    for i in $(seq 1 100); do curl -s -o /dev/null  http://myservice.net/computer; done


cleanup
#**************************************************************************************************************

function cleanup()
{
    kubectl delete namespace myservice
    MYSERVICE_V1_POD_NAME="";
    MYSERVICE_CLUSTERIP="";
    TEST_POD_NAME="";
    INGRESS_PORT="";
    SECURE_INGRESS_PORT="";
    INGRESS_HOST="";  
    GATEWAY_URL="";
    GATEWAY_CLUSTERIP="";
}
#*******************************************************************************************************************


