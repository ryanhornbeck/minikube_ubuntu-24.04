# Orbitalys Prototype: Local Kubernetes Deployment (Minikube on Ubuntu 24.04)

This README describes how to deploy the **Orbitalys prototype** locally on **Ubuntu 24.04 LTS** (e.g., in a VirtualBox VM) using a single Bash script. The deployment is **production-aware** (Keycloak, Helm stack, observability) but optimized for local development.

---

## Contents

- `deploy_orbitalys_proto.sh` — one-shot installer that provisions:
  - Docker, kubectl, Helm, Minikube
  - Namespaces: `platform`, `discovery`, `data`, `ops`
  - Ingress, metrics-server, local registry
  - **Keycloak** (Bitnami, embedded Postgres for prototype)
  - Placeholder **API** (httpbin), **Worker** (busybox loop), **Admin UI** (nginx)
  - **kube-prometheus-stack** (Prometheus + Grafana), **Loki/Promtail**, **OpenTelemetry Collector**

The script will print your access URLs upon completion.

---

## Prerequisites

- Ubuntu **24.04 LTS** (recommended) with internet access
- A user with `sudo` privileges
- VM resources (recommended minimum):
  - **6 vCPU**, **12 GB RAM**, **40 GB** disk
- Port **80** free on the host (Ingress uses `nip.io` with your Minikube IP)

> If this is a fresh VM, a reboot after Docker installation may be needed for the `docker` group to take effect.

---

## Quick Start

1. **Download and make executable**
   ```bash
   chmod +x deploy_orbitalys_proto.sh
   ```

2. **Run the installer**
   ```bash
   ./deploy_orbitalys_proto.sh
   ```

3. **Open the UI**
   - The script prints a host like: `http://orbitalys.<MINIKUBE_IP>.nip.io/`
   - API placeholder: `http://orbitalys.<MINIKUBE_IP>.nip.io/api`

4. **Grafana (port-forward)**
   ```bash
   kubectl -n ops port-forward svc/kube-prometheus-stack-grafana 3000:80
   # open http://localhost:3000  (user: admin | pass: Grafana_Orbitalys1!)
   ```

5. **Keycloak (port-forward)**
   ```bash
   kubectl -n platform port-forward svc/keycloak 8080:80
   # open http://localhost:8080  (user/pass set via env; defaults below)
   ```

---

## Configuration (Environment Variables)

| Variable | Default | Description |
|---|---|---|
| `MINIKUBE_CPUS` | `6` | CPUs for Minikube Docker driver |
| `MINIKUBE_MEMORY_MB` | `12288` | Memory (MB) for Minikube |
| `MINIKUBE_DISK_MB` | `40000` | Disk size (MB) for Minikube |
| `MINIKUBE_DRIVER` | `docker` | Minikube driver (`docker` recommended inside Ubuntu VM) |
| `KUBECTL_VERSION` | latest stable | kubectl version (e.g., `v1.30.4`) |
| `HELM_VERSION` | `v3.14.4` | Helm version to install |
| `KC_ADMIN_USER` | `admin` | Keycloak admin username |
| `KC_ADMIN_PASSWORD` | `ChangeMe_Orbitalys1!` | Keycloak admin password |
| `API_IMAGE`/`API_TAG` | `kennethreitz/httpbin:latest` | Placeholder API image |
| `WORKER_IMAGE`/`WORKER_TAG` | `busybox:stable` | Placeholder worker image |
| `UI_IMAGE`/`UI_TAG` | `nginx:stable` | Placeholder UI image |

**Example override:**
```bash
MINIKUBE_CPUS=8 MINIKUBE_MEMORY_MB=16384 KC_ADMIN_PASSWORD='S3cure!' ./deploy_orbitalys_proto.sh
```

---

## What the Script Installs

1. **Core toolchain**: Docker, kubectl, Helm, Minikube  
2. **Minikube cluster** with addons: `ingress`, `metrics-server`, `registry`  
3. **Namespaces**: `platform`, `discovery`, `data`, `ops`  
4. **Keycloak** (Bitnami) with embedded PostgreSQL (**prototype only**)  
5. **API/Worker placeholders** in `discovery`  
6. **Admin UI placeholder** (nginx) in `platform` with a basic `index.html`  
7. **Ingress** using `nip.io` (no DNS setup needed)  
8. **Observability**: kube-prometheus-stack (Prometheus + Grafana), Loki + Promtail, OpenTelemetry Collector  
9. **NetworkPolicies**: default deny in `discovery`, DNS egress allow

---

## Replacing Placeholders with Your Services

Build and deploy your own images directly into Minikube’s Docker:

```bash
# point Docker CLI to Minikube's daemon
eval $(minikube -p minikube docker-env)

# Build your API image
docker build -t myapi:dev ./api

# Update deployment to use your image
kubectl -n discovery set image deploy/api api=myapi:dev
```

For the UI:
- Replace the nginx placeholder with your React build (e.g., use a Deployment pointing to an image with your built app).  
- Or mount `/usr/share/nginx/html` with a ConfigMap containing your `index.html` + assets.

---

## Troubleshooting

- **“Invalid username or token” when pushing to Git**: use SSH keys or a Personal Access Token; passwords are disabled for git over HTTPS.  
- **`docker: permission denied`**: log out/in or `newgrp docker` after installation.  
- **Ingress 404**: wait for `ingress-nginx-controller` to be `Available`, then re-check.  
- **Low resources**: reduce `MINIKUBE_CPUS`/`MINIKUBE_MEMORY_MB`, or scale down replica counts.  
- **Port conflicts**: ensure host port 80 is free (for Ingress).  
- **Keycloak/Grafana not accessible**: use the provided `kubectl port-forward` commands.

---

## Uninstall / Reset

```bash
minikube delete
```

This removes the local cluster and all deployed resources.

---

## Production Notes (EKS Awareness)

This prototype is production-aware so transition is straightforward:
- Swap Keycloak’s embedded PostgreSQL for **RDS** (Helm values: `postgresql.enabled=false`).
- Use **AWS ECR** for images, **KMS** for encryption, **IRSA** for pod IAM.
- Add **ALB/NLB** ingress, **ExternalDNS**, **cert-manager** for TLS.
- Manage secrets using **AWS Secrets Manager** + **External Secrets**.
- Enforce policies via **OPA/Gatekeeper**. Enable autoscaling with **HPA/KEDA**.
- Deploy via **Helm/ArgoCD**; provision infra via **Terraform**.

---

## License & Attribution

© Orbitalys LLC. Prototype deployment scaffolding for internal development and evaluation.
