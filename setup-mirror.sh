#!/bin/bash
echo "Check OSSM operators"
OSSM_OPERATOR=$(oc get csv -n default | grep servicemeshoperator | awk '{print $1}')
if [ "$OSSM_OPERATOR" = "" ];
then
   echo "Install OSSM operators"
   oc apply -f config/ossm-sub.yaml
fi
function check_operator(){
   STATUS=""
   while [ "$STATUS" != "Succeeded" ];
   do 
      STATUS=$(oc get csv/$1 -n default -o jsonpath='{.status.phase}')
      echo "$1 phase: $STATUS"
      if [ "$STATUS" != "Succeeded" ];
      then 
         echo "wait for 15 sec..."
         sleep 15
      fi
   done
}
oc apply -f config/kiali-operator.yaml
check_operator $(oc get csv -n default | grep kiali | awk '{print $1}')
check_operator $(oc get csv -n default | grep jaeger | awk '{print $1}')
check_operator $(oc get csv -n default | grep servicemeshoperator | awk '{print $1}')
oc wait --for condition=established --timeout=180s \
crd/servicemeshcontrolplanes.maistra.io \
crd/servicemeshmemberrolls.maistra.io \
crd/servicemeshmembers.maistra.io \
crd/kialis.kiali.io \
crd/jaegers.jaegertracing.io
echo "Setup prod-cluster"
    oc new-project prod-cluster
    oc apply -f config/smcp-prod-cluster.yaml -n prod-cluster
    echo "Wait for ServiceMeshControlPlane creation for maximum of 3 minutes ..."
    oc  wait --for=condition=Ready --timeout=180s smcp/prod-mesh -n prod-cluster
    oc get smcp/prod-mesh -n prod-cluster
    oc new-project prod-app
    oc apply -n prod-cluster -f config/smmr.yaml
    oc wait --for=condition=Ready --timeout=180s smmr/default -n prod-cluster
    oc get smmr/default -n prod-cluster
    oc apply -f config/frontend-v1-and-backend-v1.yaml -n prod-app
    oc wait --for=condition=Ready --timeout=180s  pods -l app=backend -n prod-app
    oc wait --for=condition=Ready --timeout=180s  pods -l app=frontend -n prod-app
    oc get pods -n prod-app
    DOMAIN=$(oc whoami --show-console|awk -F'apps.' '{print $2}')
    cat config/frontend-backend-istio-crd.yaml| \
    sed 's/DOMAIN/'$DOMAIN'/'| \
    sed 's/NAMESPACE/'prod-app'/'| \
    sed 's/CLUSTER/'prod-app'/' | \
    oc apply -n prod-app -f -
    oc get virtualservice/frontend -n prod-app
    FRONTEND_ROUTE=$(oc get route -n prod-cluster -o 'custom-columns=Name:.metadata.name'|grep prod-app-frontend)
    oc patch route $FRONTEND_ROUTE -n prod-cluster -p '{"spec":{"to":{"name":"istio-ingressgateway"}}}'
    FRONTEND_URL=$(oc get route $FRONTEND_ROUTE -n prod-cluster -o jsonpath='{.spec.host}')
    echo "\n************** You can access frontend app at http://$FRONTEND_URL **************\n"
    curl -v $FRONTEND_URL
echo "Setup audit-cluster"
    oc new-project audit-cluster
    oc apply -f config/smcp-audit-cluster.yaml
    echo "Wait for ServiceMeshControlPlane creation for maximum of 3 minutes ..."
    oc  wait --for=condition=Ready --timeout=180s smcp/audit-mesh -n audit-cluster
    oc get smcp/audit-mesh -n audit-cluster
    oc new-project audit-app
    cat config/smmr.yaml | sed 's/prod-app/audit-app/' | oc apply -n audit-cluster -f -
    oc wait --for=condition=Ready --timeout=180s smmr/default -n audit-cluster
    oc get smmr/default -n audit-cluster
    oc apply -f config/audit-app.yaml -n audit-app
    oc wait --for=condition=Ready --timeout=180s  pods -l app=audit -n audit-app
    oc get pods -n audit-app
    oc apply -f config/audit-istio-crd.yaml -n audit-app
echo "Service Mesh Federation"
echo "Create Root CA of prod-mesh in audit-mesh"
    PROD_MESH_CERT=$(oc get configmap -n prod-cluster istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}')
    echo $PROD_MESH_CERT > prod-mesh-cert.pem
    oc create configmap  prod-mesh-ca-root-cert -n audit-cluster  --from-file=root-cert.pem=prod-mesh-cert.pem
    rm -f prod-mesh-cert.pem
    oc get configmap prod-mesh-ca-root-cert -n audit-cluster -o jsonpath='{.data.root-cert\.pem}'
echo "Create Root CA of audit-mesh in prod-mesh"
    AUDIT_MESH_CERT=$(oc get configmap -n audit-cluster istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}')
    echo $AUDIT_MESH_CERT > audit-mesh-cert.pem
    oc create configmap  audit-mesh-ca-root-cert -n prod-cluster  --from-file=root-cert.pem=audit-mesh-cert.pem
    rm -f audit-mesh-cert.pem
    oc get configmap audit-mesh-ca-root-cert -n prod-cluster -o jsonpath='{.data.root-cert\.pem}'
echo "Configure Service Mesh Peer"
oc apply -f config/service-mesh-peer-prod.yaml
    oc apply -f  config/service-mesh-peer-audit.yaml 
    AUDIT_STATUS=$(oc get servicemeshpeer prod-mesh -o jsonpath='{.status.discoveryStatus}' -n audit-cluster | awk -F':' '{print $1}' | sed s/\{//)
    PROD_STATUS=$(oc get servicemeshpeer audit-mesh -o jsonpath='{.status.discoveryStatus}' -n prod-cluster | awk -F':' '{print $1}' | sed s/\{//)
    echo "***** Prod Cluster *****"
    oc describe servicemeshpeer audit-mesh -n prod-cluster | grep -A8 "Discovery Status:"
    echo "***** Audit Cluster *****"
    oc describe servicemeshpeer prod-mesh -n audit-cluster | grep -A8 "Discovery Status:"
    echo "Summary:"
    echo "Prod Cluster Peering Status = $PROD_STATUS"
    echo "Audit Cluster Peering Status = $AUDIT_STATUS"
echo "Export services from audit-mesh"
  oc apply -f config/service-mesh-export-service.yaml
  oc get ExportedServiceSet/prod-mesh -o jsonpath='{.status}' -n audit-cluster|jq
  oc describe exportedserviceset prod-mesh -n audit-cluster | grep -A5 "Exported Services" 
echo "Import services to prod-mesh"
oc apply -f config/service-mesh-import-service.yaml
oc describe importedserviceset/audit-mesh  -n prod-cluster | grep -A5 "Imported Services" 
echo "Configure backend virtual service of prod-mesh to mirror traffic to audit in audit-mesh"
oc apply -f config/backend-virtual-service-mirror.yaml -n prod-app
echo "Backend Service will mirror traffic to $(oc get virtualservice/backend -n prod-app -o jsonpath='{.spec.http['0'].mirror.host}')"