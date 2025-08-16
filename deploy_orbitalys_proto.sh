#!/usr/bin/env bash
set -euo pipefail

# ================================================
# Orbitalys Prototype Installer (Ubuntu 24.04 LTS)
# - Minikube (Docker driver) on Ubuntu VM
# - Namespaces: platform, discovery, data, ops
# - Infra: Ingress, Metrics, Local Registry
# - Core: Keycloak (embedded Postgres), API/Worker placeholders, Admin UI (NGINX)
# - Observability: kube-prometheus-stack, Loki, OpenTelemetry Collector
# - Ingress host: orbitalys.<MINIKUBE_IP>.nip.io
# ================================================

# ---- Config (override with env vars) ----
MINIKUBE_CPUS="${MINIKUBE_CPUS:-6}"
MINIKUBE_MEMORY_MB="${MINIKUBE_MEMORY_MB:-12288}"
MINIKUBE_DISK_MB="${MINIKUBE_DISK_MB:-40000}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"   # docker preferred inside Ubuntu VM
HELM_VERSION="${HELM_VERSION:-v3.14.4}"
KUBECTL_VERSION="${KUBECTL_VERSION:-$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)}"

KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-ChangeMe_Orbitalys1!}"

# Placeholder images (replace later with your own)
API_IMAGE="${API_IMAGE:-kennethreitz/httpbin}"
API_TAG="${API_TAG:-latest}"
WORKER_IMAGE="${WORKER_IMAGE:-busybox}"
WORKER_TAG="${WORKER_TAG:-stable}"
UI_IMAGE="${UI_IMAGE:-nginx}"
UI_TAG="${UI_TAG:-stable}"

# Colors
BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; NC="\033[0m"

log() { echo -e "${BOLD}${GREEN}[+]${NC} $*"; }
warn() { echo -e "${BOLD}${YELLOW}[!]${NC} $*"; }
err() { echo -e "${BOLD}${RED}[-]${NC} $*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || return 1; }

# ---- Preflight ----
log "Preflight checks (Ubuntu 24.04 LTS assumed)"
sudo -v

log "Installing base packages (curl, jq, conntrack, apt-transport-https, ca-certificates, gnupg)"
sudo apt-get update -y
sudo apt-get install -y curl jq conntrack apt-transport-https ca-certificates gnupg lsb-release

# ---- Docker (for Minikube driver) ----
if ! need_cmd docker; then
  log "Installing Docker Engine"
  sudo apt-get install -y docker.io
  sudo usermod -aG docker "$USER" || true
  warn "If this is your first Docker install, you may need to log out/in for group changes to apply."
else
  log "Docker already installed"
fi

# ---- kubectl ----
if ! need_cmd kubectl; then
  log "Installing kubectl ${KUBECTL_VERSION}"
  curl -fsSL -o /tmp/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl && sudo mv /tmp/kubectl /usr/local/bin/kubectl
else
  log "kubectl already installed: $(kubectl version --client --output=yaml | head -n 1 || true)"
fi

# ---- Helm ----
if ! need_cmd helm; then
  log "Installing Helm ${HELM_VERSION}"
  curl -fsSL -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -xzf /tmp/helm.tgz -C /tmp
  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
else
  log "Helm already installed: $(helm version --short || true)"
fi

# ---- Minikube ----
if ! need_cmd minikube; then
  log "Installing Minikube"
  curl -fsSL -o /tmp/minikube.deb https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
  sudo dpkg -i /tmp/minikube.deb
else
  log "Minikube already installed: $(minikube version || true)"
fi

# ---- Start Minikube ----
if ! minikube status >/dev/null 2>&1; then
  log "Starting Minikube (driver=${MINIKUBE_DRIVER}, cpus=${MINIKUBE_CPUS}, mem=${MINIKUBE_MEMORY_MB}MB, disk=${MINIKUBE_DISK_MB}MB)"
  minikube start \
    --driver="${MINIKUBE_DRIVER}" \
    --cpus="${MINIKUBE_CPUS}" \
    --memory="${MINIKUBE_MEMORY_MB}" \
    --disk-size="${MINIKUBE_DISK_MB}mb" \
    --kubernetes-version="stable"
else
  log "Minikube already running"
fi

# ---- Enable addons ----
log "Enabling Minikube addons: ingress, metrics-server, registry"
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable registry

# ---- Namespaces ----
log "Creating namespaces (platform, discovery, data, ops)"
kubectl get ns platform >/dev/null 2>&1 || kubectl create ns platform
kubectl get ns discovery >/dev/null 2>&1 || kubectl create ns discovery
kubectl get ns data >/dev/null 2>&1 || kubectl create ns data
kubectl get ns ops >/dev/null 2>&1 || kubectl create ns ops

# ---- Helm repos ----
log "Adding/updating Helm repositories"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update

# ---- Keycloak (embedded Postgres for simplicity) ----
# Note: For production, use external RDS and disable embedded DB.
log "Deploying Keycloak (embedded Postgres) into 'platform' namespace"
kubectl -n platform create secret generic keycloak-admin-cred \
  --from-literal=username="${KC_ADMIN_USER}" \
  --from-literal=password="${KC_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install keycloak bitnami/keycloak \
  --namespace platform \
  --set auth.existingSecret=keycloak-admin-cred \
  --set production=true \
  --set proxy=edge \
  --set replicaCount=1 \
  --set postgresql.enabled=true \
  --set postgresql.primary.persistence.enabled=false \
  --wait

# ---- API & Worker placeholders (discovery ns) ----
log "Deploying API & Worker placeholders (discovery)"
cat <<EOF | kubectl apply -n discovery -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: api }
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: api
          image: ${API_IMAGE}:${API_TAG}
          ports: [{ containerPort: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: api }
spec:
  selector: { app: api }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: worker }
spec:
  replicas: 1
  selector: { matchLabels: { app: worker } }
  template:
    metadata: { labels: { app: worker } }
    spec:
      containers:
        - name: worker
          image: ${WORKER_IMAGE}:${WORKER_TAG}
          command: ["sh","-c","while true; do echo 'worker tick'; sleep 30; done"]
EOF

# ---- Admin UI (nginx + configmap) ----
log "Deploying Admin UI placeholder (platform)"
cat <<'EOF' | kubectl apply -n platform -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ui-index
data:
  index.html: |
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>Orbitalys Prototype</title></head>
    <body style="font-family: sans-serif; background: #0b1220; color: #e3e7ef;">
      <h1>Orbitalys Prototype</h1>
      <p>UI placeholder is running. Replace with your React build.</p>
      <ul>
        <li><a href="/api">/api</a> (proxied to API placeholder)</li>
        <li><a href="/auth">/auth</a> (Keycloak admin via port-forward, see notes)</li>
      </ul>
    </body></html>
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: ui }
spec:
  replicas: 1
  selector: { matchLabels: { app: ui } }
  template:
    metadata: { labels: { app: ui } }
    spec:
      containers:
        - name: nginx
          image: nginx:stable
          ports: [{ containerPort: 80 }]
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: html
          configMap:
            name: ui-index
---
apiVersion: v1
kind: Service
metadata: { name: ui }
spec:
  selector: { app: ui }
  ports: [{ port: 80, targetPort: 80 }]
EOF

# ---- Ingress (uses nip.io with Minikube IP) ----
MINIKUBE_IP=$(minikube ip)
HOST="orbitalys.${MINIKUBE_IP}.nip.io"
log "Creating Ingress at host: ${HOST}"

cat <<EOF | kubectl apply -n platform -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ui-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ui
                port:
                  number: 80
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
EOF

# ---- Observability: Prometheus/Grafana (kube-prometheus-stack) ----
log "Installing kube-prometheus-stack (Prometheus & Grafana) in 'ops'"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace ops --create-namespace \
  --set grafana.adminUser=admin \
  --set grafana.adminPassword="Grafana_Orbitalys1!" \
  --set grafana.service.type=ClusterIP \
  --wait

# ---- Loki Stack (logs) ----
log "Installing Loki Stack"
helm upgrade --install loki grafana/loki-stack \
  --namespace ops \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --wait

# ---- OpenTelemetry Collector (minimal) ----
log "Installing OpenTelemetry Collector (minimal config)"
cat <<'EOF' | kubectl apply -n ops -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: otc-config
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          http:
          grpc:
    processors:
      batch: {}
    exporters:
      logging:
        loglevel: info
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [logging]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: otelcol
spec:
  replicas: 1
  selector:
    matchLabels: { app: otelcol }
  template:
    metadata:
      labels: { app: otelcol }
    spec:
      containers:
        - name: otelcol
          image: otel/opentelemetry-collector:0.111.0
          args: ["--config=/conf/config.yaml"]
          volumeMounts:
            - name: conf
              mountPath: /conf
      volumes:
        - name: conf
          configMap:
            name: otc-config
---
apiVersion: v1
kind: Service
metadata:
  name: otelcol
spec:
  selector: { app: otelcol }
  ports:
    - name: grpc
      port: 4317
      targetPort: 4317
    - name: http
      port: 4318
      targetPort: 4318
EOF

# ---- NetworkPolicies (baseline isolation) ----
log "Applying baseline NetworkPolicies"
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: discovery
spec:
  podSelector: {}
  policyTypes: ["Ingress","Egress"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-namespace-dns
  namespace: discovery
spec:
  podSelector: {}
  policyTypes: ["Egress"]
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
EOF

# ---- Wait for ingress to be ready ----
log "Waiting for ingress controller to be ready..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s || true

# ---- Output endpoints ----
echo -e "\n${BOLD}=== Deployment Complete ===${NC}"
echo -e "UI:        ${GREEN}http://${HOST}/${NC}"
echo -e "API:       ${GREEN}http://${HOST}/api${NC} (httpbin placeholder)"
echo -e "Grafana:   ${GREEN}kubectl -n ops port-forward svc/kube-prometheus-stack-grafana 3000:80${NC}  (user: admin | pass: Grafana_Orbitalys1!)"
echo -e "Keycloak:  ${GREEN}kubectl -n platform port-forward svc/keycloak 8080:80${NC}  (user: ${KC_ADMIN_USER} | pass: ${KC_ADMIN_PASSWORD})"
echo -e "\nTo build/push your own images inside Minikube Docker:"
echo -e "  ${YELLOW}eval \$(minikube -p minikube docker-env)${NC}"
echo -e "  ${YELLOW}docker build -t myapi:dev ./api && kubectl -n discovery set image deploy/api api=myapi:dev${NC}"
echo -e "\nTo delete everything:"
echo -e "  ${YELLOW}minikube delete${NC}"
