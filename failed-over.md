# Federation across OpenShift Cluster
- [Federation across OpenShift Cluster](#federation-across-openshift-cluster)
  - [Setup](#setup)
  - [Setup Control Plane](#setup-control-plane)
  - [Configure Service Mesh Federation](#configure-service-mesh-federation)
    - [CA Root Certificate](#ca-root-certificate)
    - [Service Mesh Peering](#service-mesh-peering)
    - [Cleanup](#cleanup)
## Setup

- Set context for cluster dc1 and dc2
  
  - Login to dc1 with CLI then run following command to set context 
  
    ```bash
    oc config rename-context $(oc config current-context) dc1
    ```
  
  - Login to dc2
  
    ```bash then run following command to set context 
    oc config rename-context $(oc config current-context) dc2
    ```
## Setup Control Plane
- Create control plane for dc1 and dc2
  
  - DC1
    
    ```bash
    oc config use-context dc1
    oc new-project dc1-istio-system
    oc apply -f config/smcp-dc1.yaml
    echo "Wait for ServiceMeshControlPlane creation for maximum of 3 minutes ..."
    oc  wait --for=condition=Ready --timeout=180s smcp/dc1-mesh -n dc1-istio-system
    oc get smcp/dc1-mesh -n dc1-istio-system  
    ```

  - DC2
    
    ```bash
    oc config use-context dc2
    oc new-project dc2-istio-system
    oc apply -f config/smcp-dc2.yaml
    echo "Wait for ServiceMeshControlPlane creation for maximum of 3 minutes ..."
    oc  wait --for=condition=Ready --timeout=180s smcp/dc2-mesh -n dc2-istio-system
    oc get smcp/dc2-mesh -n dc2-istio-system  
    ```
  
- Create namespace for application, join namespace to control plane
  
  - DC1
    
    ```bash
    oc config use-context dc1
    oc new-project dc1-app
    cat config/smmr-blank.yaml | sed s/NAMESPACE/dc1-app/ | oc apply -n dc1-istio-system -f -
    oc wait --for=condition=Ready --timeout=180s smmr/default -n dc1-istio-system
    oc get smmr/default -n dc1-istio-system
    ```

  - DC2

    ```bash
    oc config use-context dc2
    oc new-project dc2-app
    cat config/smmr-blank.yaml | sed s/NAMESPACE/dc2-app/ | oc apply -n dc2-istio-system -f -
    oc wait --for=condition=Ready --timeout=180s smmr/default -n dc2-istio-system
    oc get smmr/default -n dc2-istio-system
    ```
- Deploy application to DC1 and DC2 
  - DC1
  ```bash
  oc config use-context dc1
  oc apply -f config/frontend-v1-and-backend-v1.yaml -n dc1-app
  oc wait --for=condition=Ready --timeout=180s  pods -l app=backend -n dc1-app
  oc wait --for=condition=Ready --timeout=180s  pods -l app=frontend -n dc1-app
  oc get pods -n dc1-app
  DOMAIN=$(oc whoami --show-console|awk -F'apps.' '{print $2}')
  cat config/frontend-backend-istio-crd.yaml|sed 's/DOMAIN/'$DOMAIN'/'|sed 's/NAMESPACE/'dc1-app'/'|sed 's/CLUSTER/'dc1'/'| oc apply -n dc1-app -f -
  oc get virtualservice/frontend -n dc1-app
  FRONTEND_DC1_ROUTE=$(oc get route -n dc1-istio-system -o 'custom-columns=Name:.metadata.name'|grep dc1-app-frontend)
  oc patch route $FRONTEND_DC1_ROUTE -n dc1-istio-system -p '{"spec":{"to":{"name":"istio-ingressgateway"}}}'
  FRONTEND_DC1_URL=$(oc get route $FRONTEND_DC1_ROUTE -n dc1-istio-system -o jsonpath='{.spec.host}')
  echo "\n************** You can access DC1 frontend app at http://$FRONTEND_DC1_URL **************\n"
  curl -v $FRONTEND_DC1_URL
  ```
  - DC2
  ```bash
  oc config use-context dc2
  oc apply -f config/frontend-v1-and-backend-v1.yaml -n dc2-app
  oc wait --for=condition=Ready --timeout=180s  pods -l app=backend -n dc2-app
  oc wait --for=condition=Ready --timeout=180s  pods -l app=frontend -n dc2-app
  oc get pods -n dc2-app
  DOMAIN=$(oc whoami --show-console|awk -F'apps.' '{print $2}')
  cat config/frontend-backend-istio-crd.yaml|sed 's/DOMAIN/'$DOMAIN'/'|sed 's/NAMESPACE/'dc2-app'/'|sed 's/CLUSTER/'dc2'/'| oc apply -n dc2-app -f -
  oc get virtualservice/frontend -n dc2-app
  FRONTEND_DC2_ROUTE=$(oc get route -n dc2-istio-system -o 'custom-columns=Name:.metadata.name'|grep dc2-app-frontend)
  oc patch route $FRONTEND_DC2_ROUTE -n dc2-istio-system -p '{"spec":{"to":{"name":"istio-ingressgateway"}}}'
  FRONTEND_DC2_URL=$(oc get route $FRONTEND_DC2_ROUTE -n dc2-istio-system -o jsonpath='{.spec.host}')
  echo "\n************** You can access DC2 frontend app at http://$FRONTEND_DC2_URL **************\n"
  curl -v $FRONTEND_DC2_URL
  ```

## Configure Service Mesh Federation

### CA Root Certificate

- Get CA root certificate of dc1 and create configmap at dc2

    ```bash
    oc config use-context dc1
    DC1_MESH_CERT=$(oc get configmap -n dc1-istio-system istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}')
    echo $DC1_MESH_CERT > dc1-mesh-cert.pem
    oc config use-context dc2
    oc create configmap  dc1-mesh-ca-root-cert -n dc2-istio-system  --from-file=root-cert.pem=dc1-mesh-cert.pem
    rm -f dc1-mesh-cert.pem
    oc get configmap dc1-mesh-ca-root-cert -n dc2-istio-system -o jsonpath='{.data.root-cert\.pem}'
    ```

- Get CA root certificate of dc2 and create configmap at dc1
    
    ```bash
    oc config use-context dc2
    DC2_MESH_CERT=$(oc get configmap -n dc2-istio-system istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}')
    echo $DC2_MESH_CERT > dc2-mesh-cert.pem
    oc config use-context dc1
    oc create configmap  dc2-mesh-ca-root-cert -n dc1-istio-system  --from-file=root-cert.pem=dc2-mesh-cert.pem
    rm -f dc2-mesh-cert.pem
    oc get configmap dc2-mesh-ca-root-cert -n dc1-istio-system -o jsonpath='{.data.root-cert\.pem}'
    ```

### Service Mesh Peering
- Get Service IP and node port of mesh ingress
  
  ```bash
  oc config use-context dc1
  DC1_ADDRESS=$(oc get svc dc2-mesh-ingress -n dc1-istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  DC1_DISCOVERY_PORT=$(oc get svc dc2-mesh-ingress -n dc1-istio-system -o json | jq '.spec.ports[] | select (.name == "https-discovery") | .nodePort')
  DC1_SERVICE_PORT=$(oc get svc dc2-mesh-ingress -n dc1-istio-system -o json | jq '.spec.ports[] | select (.name == "tls") | .nodePort')
  oc config use-context dc2
  DC2_ADDRESS=$(oc get svc dc1-mesh-ingress -n dc2-istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  DC2_DISCOVERY_PORT=$(oc get svc dc1-mesh-ingress -n dc2-istio-system -o json | jq '.spec.ports[] | select (.name == "https-discovery") | .nodePort')
  DC2_SERVICE_PORT=$(oc get svc dc1-mesh-ingress -n dc2-istio-system -o json | jq '.spec.ports[] | select (.name == "tls") | .nodePort')
  echo "DC1 Configuration"
  echo "dc2-mesh-ingress = $DC1_ADDRESS"
  echo "Discovery port = $DC1_DISCOVERY_PORT"
  echo "Service port = $DC1_SERVICE_PORT"
  echo "DC2 Configuration"
  echo "dc1-mesh-ingress = $DC2_ADDRESS"
  echo "Discovery port = $DC2_DISCOVERY_PORT"
  echo "Service port = $DC2_SERVICE_PORT"
  ```

- Create ServiceMeshPeer
  - DC1
    
    ```bash
    oc config use-context dc1
    cat config/service-mesh-peer-dc1.yaml | sed 's/ADDRESS/'$DC2_ADDRESS'/' | sed 's/DISCOVERY_PORT/'$DC2_DISCOVERY_PORT'/'| sed 's/SERVICE_PORT/'$DC2_SERVICE_PORT'/'|oc apply -n dc1-istio-system -f -
    ```

  - DC2
    
    ```bash
    oc config use-context dc2
    cat config/service-mesh-peer-dc2.yaml | sed 's/ADDRESS/'$DC2_ADDRESS'/' | sed 's/DISCOVERY_PORT/'$DC2_DISCOVERY_PORT'/'| sed 's/SERVICE_PORT/'$DC2_SERVICE_PORT'/'|oc apply -n dc2-istio-system -f -
    ```
- Check ServiceMeshPeer status

  ```bash
  oc describe servicemeshpeer dc2-mesh -n dc1-istio-system|grep -A8 "Discovery Status:"
  oc describe servicemeshpeer dc1-mesh -n dc2-istio-system|grep -A8 "Discovery Status:"
  ```


### Cleanup

```bash
oc delete servicemeshpeer dc2-mesh -n dc1-istio-system
oc delete servicemeshpeer dc1-mesh -n dc2-istio-system
oc delete smmr default -n dc1-istio-system
oc delete smmr default -n dc2-istio-system
oc delete smcp dc1-mesh -n dc1-istio-system
oc delete smcp dc2-mesh -n dc2-istio-system
oc delete all --all -n dc1-app
oc delete all --all -n dc2-app
oc delete project dc1-app
oc delete project dc2-app
oc delete project dc1-istio-system
oc delete project dc2-istio-system
```