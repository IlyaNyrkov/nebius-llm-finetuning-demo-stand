# Nebius AI Cloud MLOps Reference Architecture: Multi-Adapter LoRA Serving with vLLM

An end-to-end, declarative MLOps reference architecture and demo stand deployed entirely via Terraform on Nebius AI Cloud. This architecture addresses multi-tenant LLM serving economics by combining Kubernetes for scheduling jobs, Nebius Managed MLflow experiment tracking, and dynamic multi-adapter serving via vLLM on NVIDIA L40S GPUs.

---

## 1. Business Problem & Architectural Rationale

### The Enterprise Challenge

Enterprise platform teams frequently face severe cost inefficiency when operationalizing specialized language models for coding across multiple business units or enterprise tenants:

* **Dedicated Deployment Scatter:** Hosting dedicated base models (e.g., Llama 3.1 8B or Mistral 7B) for each fine-tuned domain variant results in inneficcient usage of GPUs.
* **Operational Overhead:** Deploying and lifecycle-managing distinct MLflow servers, relational metadata databases and storage connectors across ephemeral compute clusters introduces significant operational debt and configuration drift.

### The Solution

This reference architecture provides a unified control and data plane:

1. **Dynamic Multi-LoRA Multiplexing:** A single vLLM inference engine loads a base foundation model into GPU VRAM once, while dynamically loading and swapping fine-tuned LoRA adapters (<100 MB each) in real time based on request headers. E.g. separate adapters for SQL code and python code.


2. **Managed Platform State:** Experiment tracking, metric visualization, and model registry artifacts are offloaded to **Nebius Managed MLflow**, cleanly decoupling state and metrics from ephemeral worker nodes.


3. **Zero-ClickOps Automation:** The entire topology-VPC, subnets, Object Storage buckets, Managed Kubernetes (MK8s), node auto-scalers, and service accounts-is provisioned deterministically with Terraform in under 20 minutes.



---

## 2. Architecture and quota/resource requirements

![](docs/architecture.png)

- Kubernetes cluster: 1 node GPU (minimum configuration H100/H200/L40S), 1 node CPU only 2CPU-8RAM-100GB
- S3 Bucket with 100MB minimum (or unlimited)
- Managed MLFLOW instance

## 3. Tech stack

![](docs/techstack.png)

## 4. Repository Structure

```text
├── docs/
│   └── architecture.png 
├── terraform/
│   ├── network.tf                   
|   ├── kubernetes.tf
│   ├── s3-storage.tf
│   ├── terraform.tf
│   ├── providers.tf
└── k8s/
    ├── training/
    └── app/
```

---

## 5. Deployment Prerequisites

* **Nebius CLI:** Installed and authenticated (`nebius auth login`).
* **Terraform:** `>= 1.5.0`.
* **Kubectl & Helm:** Installed locally (`kubectl >= 1.28`, `helm >= 3.12`).
* **IAM Permissions:** Project Editor or equivalent permissions on the target Nebius container/folder.

---

## 6. Step-by-Step Installation

### Step 1: Provision Infrastructure via Terraform

Clone the repository and initialize the Terraform state:

```bash
git clone https://github.com/IlyaNyrkov/nebius-llm-finetuning-demo-stand.git
cd nebius-llm-finetuning-demo-stand/terraform

export NEBIUS_IAM_TOKEN=$(nebius iam get-access-token)
terraform init
terraform plan
terraform apply -auto-approve

```

### Step 2: Configure Cluster Access & Storage Secrets

Retrieve the cluster credentials using the Nebius CLI and extract output endpoints:

```bash
# List clusters to retrieve cluster ID
nebius mk8s cluster list

# Export kubeconfig for external access
nebius mk8s cluster get-credentials --id <CLUSTER_ID> --external

# Verify cluster connectivity and GPU worker nodes
kubectl get nodes -o wide

```

Sync storage credentials to the cluster so training pods and vLLM can access Nebius Object Storage buckets:

```bash
kubectl create secret generic nebius-storage-creds \
  --from-literal=AWS_ACCESS_KEY_ID=$(terraform output -raw storage_access_key_id) \
  --from-literal=AWS_SECRET_ACCESS_KEY=$(terraform output -raw storage_secret_key) \
  --namespace=default

```

### Step 3: Execute Batch Fine-Tuning Job

Trigger the PyTorch LoRA fine-tuning Job on the GPU node pool. The Job pulls the training dataset slice, runs PEFT, streams loss/eval curves to Managed MLflow, and saves the adapter weights:

```bash
kubectl apply -k k8s/training/overlays/sql-expert

# Follow training logs in real time
kubectl logs -f jobs/llm-lora-finetune-sql-expert -c trainer
```

### Step 4: Deploy vLLM Multi-Adapter Serving Engine

Deploy vLLM configured with `--enable-lora` and pre-load adapter references via Helm:

```bash
helm repo add vllm https://vllm-project.github.io/production-stack
helm repo update

helm upgrade --install vllm-engine vllm/vllm \
  -f ../k8s/serving/vllm-values.yaml \
  --namespace=default

kubectl apply -f ../k8s/serving/ingress.yaml

```

Wait until the vLLM pod is in `Running` state and the base model is warmed in VRAM:

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vllm --timeout=600s

```

### Step 4: Deploy Mlfow in Kubernetes

Add bitnami helm repository

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

Install PostgreSQL into the monitoring namespace

```bash
helm install mlflow-db bitnami/postgresql \
  --namespace monitoring \
  --set auth.username=mlflow \
  --set auth.password=mlflow123 \
  --set auth.database=mlflow \
  --set primary.persistence.size=10Gi
```

install MLflow using k8s/mlflow-values.yml configuration 

```bash
helm repo add community-charts https://community-charts.github.io/helm-charts
helm repo update

helm install mlflow community-charts/mlflow \
  --namespace monitoring \
  -f k8s/mlflow-values.yaml
```

Mlflow ui can be accessed via service ip

```bash
kubectl get svc mlflow -n monitoring
```

```bash
http://<EXTERNAL_IP>:5000
```
---

## 6. Live Demonstration Walkthrough

### 1. Verification of Base Model Inference

Send a prompt to the base model (`meta-llama/Llama-3.1-8B-Instruct` or `Qwen/Qwen2.5-Coder-7B-Instruct`) without adapter modification:

```bash
INGRESS_IP=$(kubectl get svc vllm-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -s http://${INGRESS_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-Coder-7B-Instruct",
    "messages": [
      {"role": "user", "content": "How do I query all active users from a database?"}
    ],
    "temperature": 0.0
  }' | jq '.choices[0].message.content'

```

*Expected Output:* Conversational, natural-language explanation covering general SQL syntax and conceptual tips.

---

### 2. Live Dynamic LoRA Swap

Send the same request specifying the registered LoRA adapter name. vLLM loads the adapter weights dynamically into remaining VRAM without restarting the engine or dropping connections:

```bash
curl -s http://${INGRESS_IP}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "sql-expert-lora",
    "messages": [
      {"role": "user", "content": "How do I query all active users from a database?"}
    ],
    "temperature": 0.0
  }' | jq '.choices[0].message.content'

```

*Expected Output:* Strictly formatted, deterministic, schema-compliant SQL query with production indexing hints, demonstrating domain specialization.

---

### 3. Observability & Tracking Metrics

* **Nebius Managed MLflow UI:** Direct the browser to the MLflow tracking endpoint from `terraform output mlflow_endpoint`. Review training epochs, training loss vs. evaluation loss, and the registered adapter artifact lineage.


* **vLLM Metrics:** Query Prometheus metrics on the vLLM service (`http://${INGRESS_IP}/metrics`) to inspect:
* `vllm:num_requests_running`: Real-time request concurrency.
* `vllm:gpu_cache_usage_factor`: KV cache VRAM utilization.
* `vllm:time_to_first_token_seconds`: Pre-fill and dynamic adapter lookup latency.

---

## 7. Clean-Up & Cost Governance

To avoid idle cloud spend against your promotional credit balance, tear down all provisioned resources immediately after the presentation:

```bash
# 1. Remove Kubernetes Helm deployments and Jobs to release volume claims
kubectl delete -f ../k8s/training/job-finetune.yaml --ignore-not-found
helm uninstall vllm-engine --namespace=default

# 2. Destroy all cloud infrastructure (MK8s, MLflow, Object Storage, VPC)
cd ../terraform
terraform destroy -auto-approve

```