#!/bin/bash

# enable ingress if required
minikube addons enable ingress && \
kubectl -n ingress-nginx rollout status deployment.apps/ingress-nginx-controller

# install backend-ns if required
FOUND_NS=kubectl get ns backend-ns
if [[ ${FOUND_NS} == "" ]]; then
    kubectl create namespace backend-ns
fi

# install keycloak-ns if required
FOUND_NS=""
FOUND_NS=kubectl get ns keycloak-ns
if [[ ${FOUND_NS} == "" ]]; then
    kubectl create namespace keycloak-ns
fi

# install monitoring if required
FOUND_NS=""
FOUND_NS=kubectl get ns monitoring
if [[ ${FOUND_NS} == "" ]]; then
    kubectl create namespace monitoring
fi

# install users-db-ns if required
FOUND_NS=""
FOUND_NS=kubectl get ns users-db-ns
if [[ ${FOUND_NS} == "" ]]; then
    kubectl create namespace users-db-ns
fi

# install cloud native
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-1.24.0.yaml && \
kubectl wait --for condition=established crd/clusters.postgresql.cnpg.io crd/clusterimagecatalogs.postgresql.cnpg.io && \
kubectl -n cnpg-system rollout status deployment.apps/cnpg-controller-manager

# install cert manager
kubectl apply -f ./helm/backend-chart/charts/helm-cert-manager/templates/cert-manager.yaml && \
kubectl wait --for condition=established crd/certificates.cert-manager.io crd/issuers.cert-manager.io && \
kubectl -n cert-manager rollout status deployment.apps/cert-manager-webhook

# install reflector to propagate secrets across namespaces
kubectl apply -f https://github.com/emberstack/kubernetes-reflector/releases/latest/download/reflector.yaml

# install prometheus-crds
kubectl apply --server-side -f helm/backend-chart/charts/helm-prometheus-crds/templates

# dry-run
#helm template --dry-run --debug \
#    --set global.keycloakNs=keycloak-ns \
#    --set global.dnsName=front-keycloak.com \
#    ./helm/backend-chart/charts/helm-keycloak

# install certificates
helm upgrade --install \
    --atomic \
    --timeout 30m \
    --wait \
    --wait-for-jobs \
    --namespace backend-ns \
    --set global.keycloakNs=keycloak-ns \
    --set global.dnsName=front-keycloak.com \
    --set global.monitoringNs=monitoring \
    --set global.grafanaSecretName=grafana-cert-ca-secret \
    --set global.dnsGrafana=grafana-monitoring.com \
    helm-cert-manager \
    ./helm/backend-chart/charts/helm-cert-manager

# dry-run
#helm template --dry-run --debug \
#    --set keycloak.keycloakAdmin=$KEYCLOAK_ADMIN \
#    --set keycloak.keycloakAdminPassword=$KEYCLOAK_ADMIN_PASSWORD \
#    --set postgres.keycloakDBOwner=$KEYCLOAK_DB_OWNER \
#    --set postgres.keycloakDBPassword=$KEYCLOAK_DB_PASSWORD \
#    --set global.keycloakNs=keycloak-ns \
#    --set global.dnsName=front-keycloak.com \
#    ./helm/backend-chart/charts/helm-keycloak

# install & upgrade keycloak chart
helm upgrade --install \
    --atomic \
    --timeout 30m \
    --wait \
    --wait-for-jobs \
    --namespace backend-ns \
    --set keycloak.keycloakAdmin=$KEYCLOAK_ADMIN \
    --set keycloak.keycloakAdminPassword=$KEYCLOAK_ADMIN_PASSWORD \
    --set postgres.keycloakDBOwner=$KEYCLOAK_DB_OWNER \
    --set postgres.keycloakDBPassword=$KEYCLOAK_DB_PASSWORD \
    --set global.keycloakNs=keycloak-ns \
    --set global.dnsName=front-keycloak.com \
    helm-keycloak \
    ./helm/backend-chart/charts/helm-keycloak

# install & upgrade users-db chart
helm upgrade --install \
    --atomic \
    --timeout 30m \
    --wait \
    --wait-for-jobs \
    --namespace backend-ns \
    --set postgres.dbOwner=$USERS_DB_OWNER \
    --set postgres.dbPassword=$USERS_DB_PASSWORD \
    helm-users-db \
    ./helm/backend-chart/charts/helm-users-db

# install & upgrade prometheus-chart
helm upgrade --install \
    --atomic \
    --timeout 30m \
    --wait \
    --wait-for-jobs \
    --namespace backend-ns \
    --set global.monitoringNs=monitoring \
    --set global.alertmanagerName=main-alertmanager \
    --set global.rule.ruleName=business-users-backend-rule \
    --set global.rule.name="business error users-backend rule" \
    helm-prometheus \
    ./helm/backend-chart/charts/helm-prometheus

# install prometheus alert manager
helm upgrade --install \
    --atomic \
    --timeout 30m \
    --wait \
    --wait-for-jobs \
    --namespace backend-ns \
    --set global.monitoringNs=monitoring \
    --set global.alertmanagerName=main-alertmanager \
    --set global.rule.ruleName=business-users-backend-rule \
    --set email.emailSendTo=$EMAIL_SEND_TO \
    --set email.emailSendFrom=$EMAIL \
    --set email.username=$EMAIL \
    --set email.password=$EMAIL_PASS \
    --set email.host=$EMAIL_HOST \
    --set email.port='587' \
    helm-prometheus-alertmanager \
    ./helm/backend-chart/charts/helm-prometheus-alertmanager

# install loki simple scalable version, promtail, grafana
# helm repo add grafana https://grafana.github.io/helm-charts
# helm repo update
helm upgrade --install \
 loki \
  --namespace=monitoring \
 --values ./helm/backend-chart/charts/helm-grafana-loki/templates/grafana-loki-values.yaml \
 grafana/loki-stack

 # install grafana ingress
 helm upgrade --install \
 --atomic \
 --timeout 1m \
 --wait \
 --wait-for-jobs \
 --namespace backend-ns \
 --set global.monitoringNs=monitoring \
 --set global.grafanaSecretName=grafana-cert-ca-secret \
 --set global.dnsGrafana=grafana-monitoring.com \
 helm-grafana-ingress \
 ./helm/backend-chart/charts/helm-grafana-loki

kubectl create ingress grafana-ingress -n monitoring -f ./helm/backend-chart/charts/helm-grafana-loki/templates/ingress.yaml

# helm repo update
# helm search repo prometheus
# helm show values prometheus-community/kube-prometheus-stack > prometheus_values.yml
# helm pull prometheus-community/prometheus

# dry-run
#helm template --dry-run --debug \
#    --set postgres.dbOwner=$USERS_DB_OWNER \
#    --set postgres.dbPassword=$USERS_DB_PASSWORD \
#    ./helm/backend-chart/charts/helm-users-db

 # dry prometheus
#helm template --dry-run --debug \
#--set global.monitoringNs=monitoring \
# --set global.alertLabelName=alertmanager \
# --set global.rule.ruleName=business-users-backend-rule \
# --set global.rule.name="business error users-backend rule" \
#helm-prometheus \
#./helm/backend-chart/charts/helm-prometheus

# get file content from keycloak secret to keycloak.crt file before adding to keystore
# add tls cert for keycloak if required

#kubectl get secret keycloak-cert-ca-secret -n keycloak-ns -o jsonpath='{.data.tls\.crt}' | base64 --decode > ./local/keycloak.crt && \
#sudo keytool -import -alias keycloak_crt -file ./local/keycloak.crt -keystore /usr/lib/jvm/jdk-17.0.1/lib/security/cacerts -storepass changeit -noprompt && \
#openssl x509 -in ./local/keycloak.crt -text -noout

 # verify if cert exists
#sudo keytool -list -keystore /usr/lib/jvm/jdk-17.0.1/lib/security/cacerts -alias keycloak_crt -storepass changeit -noprompt

 # delete cert
# sudo keytool -delete -alias keycloak_crt -keystore /usr/lib/jvm/jdk-17.0.1/lib/security/cacerts -storepass changeit -noprompt