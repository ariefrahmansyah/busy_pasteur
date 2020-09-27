#!/bin/sh

set -ex

export KIND_NODE_VERSION=v1.17.11
export KNATIVE_VERSION=v0.15.0
export ISTIO_VERSION=1.6.2
export CERT_MANAGER_VERSION=v0.15.1
export KFSERVING_VERSION=v0.4.0
export SPARK_OPERATOR_VERSION=0.6.12
export VAULT_VERSION=0.7.0

export CLUSTER_NAME=dev

# Install tools
sudo apt-get update
sudo apt-get install jq
pip3 install yq

# Provision KinD cluster
kind create cluster --name=${CLUSTER_NAME} --config=kind-config.yaml --image=kindest/node:${KIND_NODE_VERSION}

# Install Knative
kubectl apply --filename=https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-crds.yaml
kubectl apply --filename=https://github.com/knative/serving/releases/download/${KNATIVE_VERSION}/serving-core.yaml

kubectl set resources deployment activator --namespace=knative-serving --containers=activator --requests=cpu=30m,memory=64Mi --limits=cpu=300m,memory=256Mi
kubectl set resources deployment autoscaler --namespace=knative-serving --containers=autoscaler --requests=cpu=30m,memory=64Mi --limits=cpu=300m,memory=256Mi
kubectl set resources deployment controller --namespace=knative-serving --containers=controller --requests=cpu=30m,memory=64Mi --limits=cpu=300m,memory=256Mi
kubectl set resources deployment webhook --namespace=knative-serving --containers=webhook --requests=cpu=30m,memory=64Mi --limits=cpu=300m,memory=256Mi

kubectl wait deployment.apps/activator --namespace=knative-serving --for=condition=available --timeout=300s
kubectl wait deployment.apps/autoscaler --namespace=knative-serving --for=condition=available --timeout=300s
kubectl wait deployment.apps/controller --namespace=knative-serving --for=condition=available --timeout=300s
kubectl wait deployment.apps/webhook --namespace=knative-serving --for=condition=available --timeout=300s

# Install Istio
curl --location https://git.io/getLatestIstio | sh -
sudo install istio-${ISTIO_VERSION}/bin/istioctl /usr/bin/istioctl
istioctl install --filename=istio-minimal-operator.yaml

kubectl apply --filename=https://github.com/knative/net-istio/releases/download/v0.15.0/release.yaml
kubectl patch configmap/config-domain --namespace=knative-serving --type=merge --patch='{"data":{"127.0.0.1.xip.io":""}}'

# Install Cert Manager
kubectl apply --validate=false --filename=https://github.com/jetstack/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml
kubectl wait deployment/cert-manager-webhook --namespace=cert-manager --for=condition=available --timeout=600s

# Install Spark Operator
kubectl create namespace spark-operator
helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator
helm install spark-operator incubator/sparkoperator --version=${SPARK_OPERATOR_VERSION} --values=spark-operator-values.yaml --namespace=spark-operator --wait --timeout 600s

# Install KFServing
kubectl apply --filename=https://raw.githubusercontent.com/kubeflow/kfserving/master/install/${KFSERVING_VERSION}/kfserving.yaml
kubectl wait pod/kfserving-controller-manager-0 --namespace=kfserving-system --for=condition=ready --timeout=300s

# Install Vault
kubectl create namespace vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --version=${VAULT_VERSION} --values=vault-values.yaml --namespace=vault
kubectl get pods --all-namespaces
kubectl describe nodes
kubectl wait pod/vault-0 --namespace=vault --for=condition=ready --timeout=300s
# Downgrade to Vault KV secrets engine version 1
kubectl exec vault-0 --namespace=vault -- vault secrets disable secret
kubectl exec vault-0 --namespace=vault -- vault secrets enable -version=1 -path=secret kv

# Put KinD cluster credential to Vault
kind get kubeconfig > kubeconfig.yaml
cat <<EOF > cluster-credential.json
{
  "name": "$(yq -r '.clusters[0].name' kubeconfig.yaml)",
  "master_ip": "$(yq -r '.clusters[0].cluster.server' kubeconfig.yaml)",
  "certs": "$(yq -r '.clusters[0].cluster."certificate-authority-data"' kubeconfig.yaml | base64 --decode | awk '{printf "%s\\n", $0}')",
  "client_certificate": "$(yq -r '.users[0].user."client-certificate-data"' kubeconfig.yaml | base64 --decode | awk '{printf "%s\\n", $0}')",
  "client_key": "$(yq -r '.users[0].user."client-key-data"' kubeconfig.yaml | base64 --decode | awk '{printf "%s\\n", $0}')"
}
EOF
kubectl cp cluster-credential.json vault/vault-0:/tmp/cluster-credential.json
kubectl exec vault-0 --namespace=vault -- vault kv put secret/${CLUSTER_NAME} @/tmp/cluster-credential.json

set +ex
