#!/bin/bash
oc delete all --all -n prod-app
oc delete all --all -n audit-app
oc delete smmr default -n prod-cluster
oc delete smmr default -n audit-cluster
oc delete smcp prod-mesh -n prod-cluster
oc delete smcp audit-mesh -n audit-cluster
oc delete project prod-app
oc delete project prod-cluster
oc delete project audit-app
oc delete project audit-cluster