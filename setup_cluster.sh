#!/bin/sh

set -ex

export KIND_NODE_VERSION=v1.17.11
export KNATIVE_VERSION=v0.15.0
export ISTIO_VERSION=1.6.2
export CERT_MANAGER_VERSION=v0.15.1
export KFSERVING_VERSION=v0.4.0
export VAULT_VERSION=0.7.0

# Install tools
sudo apt-get update
test -x jq || sudo apt-get install jq

# Provision KinD cluster
kind create cluster --config=kind-config.yaml --image=kindest/node:${KIND_NODE_VERSION}

# # Install Knative
# kubectl apply --filename=https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml
# kubectl apply --filename=https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml
# kubectl wait deployment.apps/webhook --namespace=knative-serving --for=condition=available --timeout=300s

# # Install Istio
# curl --location https://git.io/getLatestIstio | sh -
# sudo install istio-${ISTIO_VERSION}/bin/istioctl /usr/bin/istioctl
# istioctl install --filename=istio-minimal-operator.yaml

# kubectl apply --filename=https://github.com/knative/net-istio/releases/download/v0.15.0/release.yaml
# kubectl patch configmap/config-domain --namespace=knative-serving --type=merge --patch='{"data":{"127.0.0.1.xip.io":""}}'

# # Install Cert Manager
# kubectl apply --validate=false --filename=https://github.com/jetstack/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml
# kubectl wait deployment/cert-manager-webhook --namespace=cert-manager --for=condition=available --timeout=600s

# # Install KFServing
# kubectl apply --filename=https://raw.githubusercontent.com/kubeflow/kfserving/master/install/${KFSERVING_VERSION}/kfserving.yaml
# kubectl wait pod/kfserving-controller-manager-0 --namespace=kfserving-system --for=condition=ready --timeout=300s

# Install Vault
kubectl create namespace vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --version=${VAULT_VERSION} --values=vault-values.yaml --namespace=vault
sleep 15
kubectl get pod -o yaml --namespace=vault
kubectl exec vault-0 --namespace=vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json > init.json
export UNSEAL_KEY=$(cat init.json | jq -r '.unseal_keys_b64[0]')
kubectl exec vault-0 --namespace=vault -- vault operator unseal ${UNSEAL_KEY}
kubectl wait pod/vault-0 --namespace=vault --for=condition=ready --timeout=300s

set +ex
