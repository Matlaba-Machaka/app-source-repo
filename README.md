# Zero-Secrets GitOps Pipeline on Azure (AKS + ArgoCD + OIDC)

A production-grade, end-to-end **Zero-Secrets GitOps Delivery Loop** built using native Azure enterprise capabilities. This architecture eliminates static credentials from CI/CD pipelines and prevents manual cluster configuration drift.

---

## 🎯 Problem Statement

Modern cloud-native operations often face two critical challenges:
1. **Secrets Sprawl:** Storing long-lived Azure Service Principal client secrets or passwords in GitHub Actions increases the attack surface and creates ongoing credential rotation overhead.
2. **Configuration Drift:** Manual `kubectl` edits or out-of-band changes create discrepancies between declared infrastructure and the live Azure Kubernetes Service (AKS) cluster state.

---

## 🏗️ Architecture & Workflow Overview

This solution enforces a strict **Separation of Concerns** by decoupling application source code from Kubernetes deployment manifests across two repositories:

* **`app-source-repo`**: Contains application source code, Dockerfile, and the CI pipeline.
* **`gitops-manifests-repo`**: Acts as the single source of truth for Kubernetes manifests and Helm/Kustomize configurations.

```
┌─────────────────────────┐       OIDC Token Exchange       ┌─────────────────────────┐
│     GitHub Actions      │ ──────────────────────────────► │   Microsoft Entra ID    │
│    (app-source-repo)    │ ◄────────────────────────────── │ (User-Assigned Identity)│
└────────────┬────────────┘      Short-Lived Auth Token     └─────────────────────────┘
             │
             │ 1. Build & Push Container Image
             ▼
┌─────────────────────────┐
│ Azure Container Registry│
│          (ACR)          │
└─────────────────────────┘
             │
             │ 2. Update Image Tag via PR / Commit
             ▼
┌─────────────────────────┐       Continuous Polling / Sync ┌─────────────────────────┐
│  gitops-manifests-repo  │ ◄────────────────────────────── │         ArgoCD          │
│    (Desired State)      │ ──────────────────────────────► │      (AKS Cluster)      │
└─────────────────────────┘       Declarative Self-Healing  └─────────────────────────┘
```

---

## Key Architectural Pillars

### 1. Zero-Secrets Authentication via OIDC
* **Federated Identity Credentials:** Configured an OpenID Connect (OIDC) trust relationship between a **User-Assigned Managed Identity** in Microsoft Entra ID and GitHub's OIDC provider.
* **Dynamic Token Exchange:** GitHub Actions runners request short-lived, scoped tokens at runtime to authenticate with Azure and push container images to **Azure Container Registry (ACR)**.
* **Zero Rotation Overhead:** No client secrets, certificates, or ACR admin credentials are stored in GitHub Secrets.

### 2. Two-Repository GitOps Pattern
* **CI Boundary (`app-source-repo`):** Handles unit testing, container builds, security scanning, and pushing tagged images to ACR. Once published, it updates the image tag in the state repository.
* **CD Boundary (`gitops-manifests-repo`):** Holds declarative Kubernetes YAML definitions. Changes are auditable via Git commit history and pull request approvals.

### 3. Declarative Cluster Healing with ArgoCD
* **Automated Reconciliation:** ArgoCD runs inside the **AKS cluster** and continuously monitors `gitops-manifests-repo`.
* **Self-Healing:** Any manual, out-of-band modification made directly inside the cluster is immediately flagged as `OutOfSync` and automatically reverted to match the Git baseline.

---

## Repository Structure

```text
.
├── .github/
│   └── workflows/
│       └── ci-build-push.yml       # OIDC login, Docker build, ACR push & manifest update
├── app/
│   ├── src/                        # Application source code
│   └── Dockerfile                  # Multi-stage container build definition
├── manifests/                      # (Mirrored in gitops-manifests-repo)
│   ├── base/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── kustomization.yaml
│   └── overlays/
│       └── prod/
│           └── kustomization.yaml
├── argocd/
│   └── application.yaml            # ArgoCD Application CRD pointing to manifests repo
└── README.md
```

---

## 🛠️ Tech Stack

| Component | Technology / Service | Purpose |
| :--- | :--- | :--- |
| **Cloud Provider** | Microsoft Azure | Core cloud infrastructure |
| **Identity & Access** | Microsoft Entra ID (OIDC + Managed Identity) | Passwordless CI/CD authentication |
| **Container Registry** | Azure Container Registry (ACR) | Private OCI image storage |
| **Orchestration** | Azure Kubernetes Service (AKS) | Managed Kubernetes runtime |
| **CI Engine** | GitHub Actions | Automated build and image publishing |
| **CD / GitOps Engine** | ArgoCD | Continuous reconciliation and drift healing |

---

## 🚀 Setup & Deployment Guide

### Prerequisites
* Azure Subscription with permissions to create Resource Groups, AKS, ACR, and Entra ID Managed Identities.
* Azure CLI (`az`), `kubectl`, and `argocd` CLI installed locally.
* Two GitHub repositories: `app-source-repo` and `gitops-manifests-repo`.

### Step 1: Provision Azure Infrastructure & OIDC Trust
1. Create a **User-Assigned Managed Identity** in Entra ID.
2. Assign the `AcrPush` role to the Managed Identity scoped to your **Azure Container Registry**.
3. Add a **Federated Credential** on the Managed Identity matching your GitHub organization, repository (`app-source-repo`), and target branch/environment.
4. Store only non-sensitive identifiers (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) as GitHub repository variables.

### Step 2: Bootstrap ArgoCD on AKS
```bash
# Get AKS credentials
az aks get-credentials --resource-group <YOUR_RG> --name <YOUR_AKS_CLUSTER>

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply the GitOps Application manifest
kubectl apply -f argocd/application.yaml
```

### Step 3: Trigger the Delivery Loop
1. Push a code change to `main` in `app-source-repo`.
2. GitHub Actions authenticates via OIDC, builds the image, and pushes it to ACR.
3. The workflow updates the image tag in `gitops-manifests-repo`.
4. ArgoCD detects the new commit and syncs the updated deployment onto AKS.

---

## 🧪 Testing Self-Healing (Drift Detection)

To verify that ArgoCD prevents manual configuration drift:

1. Manually scale or edit a deployment in the cluster:
   ```bash
   kubectl scale deployment <APP_NAME> --replicas=5 -n <NAMESPACE>
   ```
2. Observe ArgoCD detect the drift and immediately reconcile the replica count back to the declarative value defined in `gitops-manifests-repo`.

---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).
