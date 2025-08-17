#!/bin/bash

# Deployment script for QuotesDB
set -e

# Configuration
ENVIRONMENT=${1:-staging}
NAMESPACE="quotesdb-${ENVIRONMENT}"
IMAGE_TAG=${2:-latest}

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
    echo "Usage: $0 [development|staging|production] [image-tag]"
    exit 1
fi

log_info "Deploying QuotesDB to $ENVIRONMENT environment"

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed."; exit 1; }
command -v docker >/dev/null 2>&1 || { log_error "docker is required but not installed."; exit 1; }

# Build Docker image
log_info "Building Docker image..."
docker build -t quotesdb:${IMAGE_TAG} -f docker/Dockerfile ../quotesdb

# Tag and push to registry (adjust registry URL as needed)
REGISTRY_URL="your-registry.com"
docker tag quotesdb:${IMAGE_TAG} ${REGISTRY_URL}/quotesdb:${IMAGE_TAG}
docker push ${REGISTRY_URL}/quotesdb:${IMAGE_TAG}

# Apply Kubernetes configurations
log_info "Applying Kubernetes configurations..."

# Create namespace if it doesn't exist
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Apply configurations
kubectl apply -f kubernetes/configmap.yaml -n ${NAMESPACE}
kubectl apply -f kubernetes/secrets.yaml -n ${NAMESPACE} 2>/dev/null || log_warning "Secrets not found. Please create from template."
kubectl apply -f kubernetes/deployment.yaml -n ${NAMESPACE}
kubectl apply -f kubernetes/service.yaml -n ${NAMESPACE}
kubectl apply -f kubernetes/ingress.yaml -n ${NAMESPACE}

# Update deployment with new image
log_info "Updating deployment with image tag: ${IMAGE_TAG}"
kubectl set image deployment/quotesdb quotesdb=${REGISTRY_URL}/quotesdb:${IMAGE_TAG} -n ${NAMESPACE}

# Wait for rollout to complete
log_info "Waiting for deployment rollout..."
kubectl rollout status deployment/quotesdb -n ${NAMESPACE}

# Get deployment status
log_info "Deployment status:"
kubectl get pods -n ${NAMESPACE} -l app=quotesdb

log_info "Deployment completed successfully!"

# Display access information
INGRESS_HOST=$(kubectl get ingress quotesdb-ingress -n ${NAMESPACE} -o jsonpath='{.spec.rules[0].host}')
log_info "Application is available at: https://${INGRESS_HOST}"