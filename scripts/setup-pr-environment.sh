#!/bin/bash

# Script to set up a PR environment with database branching
set -e

PR_NUMBER=$1
BASE_BRANCH=${2:-staging}

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: $0 <PR_NUMBER> [BASE_BRANCH]"
    exit 1
fi

# Configuration
PR_NAMESPACE="quotesdb-pr-${PR_NUMBER}"
PR_DATABASE="quotesdb_pr_${PR_NUMBER}"
PR_URL="https://pr-${PR_NUMBER}.quotesdb.dev"

echo "Setting up PR environment #${PR_NUMBER}"

# Create database branch (example for PostgreSQL)
if [ -n "$DATABASE_URL" ]; then
    echo "Creating database branch: ${PR_DATABASE}"
    
    # Parse DATABASE_URL
    DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\([^:]*\).*/\1/p')
    DB_USER=$(echo $DATABASE_URL | sed -n 's/.*:\/\/\([^:]*\).*/\1/p')
    
    # Create new database from staging
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -c "CREATE DATABASE ${PR_DATABASE} WITH TEMPLATE quotesdb_staging;"
    
    # Update DATABASE_URL for PR environment
    PR_DATABASE_URL=$(echo $DATABASE_URL | sed "s/quotesdb_staging/${PR_DATABASE}/g")
fi

# Deploy to Kubernetes
echo "Deploying PR environment to Kubernetes..."

# Create namespace
kubectl create namespace ${PR_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap with PR-specific values
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: quotesdb-config
  namespace: ${PR_NAMESPACE}
data:
  nextauth-url: "${PR_URL}"
  environment: "pr-${PR_NUMBER}"
EOF

# Copy secrets from staging
kubectl get secret quotesdb-secrets -n quotesdb-staging -o yaml | \
    sed "s/namespace: .*/namespace: ${PR_NAMESPACE}/" | \
    kubectl apply -f -

kubectl get secret quotesdb-oauth -n quotesdb-staging -o yaml | \
    sed "s/namespace: .*/namespace: ${PR_NAMESPACE}/" | \
    kubectl apply -f -

# Deploy application
kubectl apply -f kubernetes/deployment.yaml -n ${PR_NAMESPACE}
kubectl apply -f kubernetes/service.yaml -n ${PR_NAMESPACE}

# Create PR-specific ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: quotesdb-ingress
  namespace: ${PR_NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - pr-${PR_NUMBER}.quotesdb.dev
    secretName: quotesdb-pr-${PR_NUMBER}-tls
  rules:
  - host: pr-${PR_NUMBER}.quotesdb.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: quotesdb-service
            port:
              number: 80
EOF

echo "PR environment created successfully!"
echo "URL: ${PR_URL}"
echo "Database: ${PR_DATABASE}"
echo "Namespace: ${PR_NAMESPACE}"