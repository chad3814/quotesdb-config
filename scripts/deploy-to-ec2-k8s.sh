#!/bin/bash

# Deployment script for QuotesDB on self-managed Kubernetes on EC2
set -e

# Configuration
ENVIRONMENT=${1:-staging}
IMAGE_TAG=${2:-latest}
MASTER_IP=${3:-}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT"
    echo "Usage: $0 [development|staging|production] [image-tag] [master-ip]"
    exit 1
fi

if [ -z "$MASTER_IP" ]; then
    log_error "Master IP is required"
    echo "Usage: $0 [development|staging|production] [image-tag] [master-ip]"
    echo "Get the master IP from Terraform output: terraform output k8s_master_public_ip"
    exit 1
fi

log_info "Deploying QuotesDB to $ENVIRONMENT environment on Kubernetes at $MASTER_IP"

# Check prerequisites
command -v docker >/dev/null 2>&1 || { log_error "docker is required but not installed."; exit 1; }
command -v ssh >/dev/null 2>&1 || { log_error "ssh is required but not installed."; exit 1; }

# Build Docker image
log_info "Building Docker image..."
docker build -t quotesdb:${IMAGE_TAG} -f ../docker/Dockerfile ../../quotesdb

# Tag and push to registry (using Docker Hub or ECR)
REGISTRY_URL="${DOCKER_REGISTRY:-docker.io/yourusername}"
docker tag quotesdb:${IMAGE_TAG} ${REGISTRY_URL}/quotesdb:${IMAGE_TAG}

log_info "Pushing image to registry..."
docker push ${REGISTRY_URL}/quotesdb:${IMAGE_TAG}

# Copy Kubernetes manifests to master node
log_info "Copying Kubernetes manifests to master node..."
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "mkdir -p ~/quotesdb-k8s"
scp -o StrictHostKeyChecking=no -r ../kubernetes/* ubuntu@${MASTER_IP}:~/quotesdb-k8s/

# Create deployment script on master
cat <<'DEPLOY_SCRIPT' | ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "cat > ~/deploy-quotesdb.sh && chmod +x ~/deploy-quotesdb.sh"
#!/bin/bash
set -e

NAMESPACE="quotesdb-${ENVIRONMENT}"
IMAGE_TAG="${IMAGE_TAG}"
REGISTRY_URL="${REGISTRY_URL}"

echo "Deploying QuotesDB..."

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Update image in deployment
sed -i "s|image: quotesdb:.*|image: ${REGISTRY_URL}/quotesdb:${IMAGE_TAG}|g" ~/quotesdb-k8s/deployment.yaml

# Apply configurations
kubectl apply -f ~/quotesdb-k8s/configmap.yaml -n ${NAMESPACE}
kubectl apply -f ~/quotesdb-k8s/secrets.yaml -n ${NAMESPACE} 2>/dev/null || echo "Warning: Secrets not found. Please create from template."
kubectl apply -f ~/quotesdb-k8s/deployment.yaml -n ${NAMESPACE}
kubectl apply -f ~/quotesdb-k8s/service.yaml -n ${NAMESPACE}

# Create NodePort service for ALB access
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: quotesdb-nodeport
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: quotesdb
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080
    protocol: TCP
EOF

# Wait for deployment
kubectl rollout status deployment/quotesdb -n ${NAMESPACE}

echo "Deployment completed!"
kubectl get pods -n ${NAMESPACE}
kubectl get svc -n ${NAMESPACE}
DEPLOY_SCRIPT

# Execute deployment on master
log_info "Executing deployment on master node..."
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "ENVIRONMENT=${ENVIRONMENT} IMAGE_TAG=${IMAGE_TAG} REGISTRY_URL=${REGISTRY_URL} ./deploy-quotesdb.sh"

log_info "Deployment completed successfully!"

# Get ALB DNS if available
if [ -f "../terraform/terraform.tfstate" ]; then
    ALB_DNS=$(terraform output -state=../terraform/terraform.tfstate -raw alb_dns_name 2>/dev/null || echo "")
    if [ -n "$ALB_DNS" ]; then
        log_info "Application is available at: http://${ALB_DNS}"
    fi
fi

log_info "You can access the Kubernetes dashboard by running:"
echo "  ssh -L 8001:localhost:8001 ubuntu@${MASTER_IP}"
echo "  Then run: kubectl proxy"
echo "  Access dashboard at: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"