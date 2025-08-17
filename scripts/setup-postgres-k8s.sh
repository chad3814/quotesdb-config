#!/bin/bash

# Script to deploy PostgreSQL on Kubernetes cluster
set -e

MASTER_IP=${1:-}
POSTGRES_PASSWORD=${2:-$(openssl rand -base64 32)}

if [ -z "$MASTER_IP" ]; then
    echo "Usage: $0 <master-ip> [postgres-password]"
    echo "If postgres-password is not provided, a random one will be generated"
    exit 1
fi

echo "Setting up PostgreSQL on Kubernetes cluster at $MASTER_IP"
echo "Generated password: $POSTGRES_PASSWORD"

# Create setup script on master
cat <<SETUP_SCRIPT | ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "cat > ~/setup-postgres.sh && chmod +x ~/setup-postgres.sh"
#!/bin/bash
set -e

echo "Deploying PostgreSQL to Kubernetes..."

# Create namespace
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: postgres
  labels:
    app: postgres
    component: database
EOF

# Create StorageClass
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: postgres-storage
  labels:
    app: postgres
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  fsType: ext4
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
EOF

# Create Secret with provided password
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: postgres
  labels:
    app: postgres
type: Opaque
stringData:
  POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
  POSTGRES_REPLICATION_PASSWORD: "${POSTGRES_PASSWORD}-repl"
  DATABASE_URL: "postgresql://quotesdb:${POSTGRES_PASSWORD}@postgres-service.postgres.svc.cluster.local:5432/quotesdb"
EOF

# Also create secret in quotesdb namespace for app access
kubectl create namespace quotesdb --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-connection
  namespace: quotesdb
  labels:
    app: quotesdb
    component: database-connection
type: Opaque
stringData:
  DATABASE_URL: "postgresql://quotesdb:${POSTGRES_PASSWORD}@postgres-service.postgres.svc.cluster.local:5432/quotesdb"
EOF

echo "PostgreSQL secrets configured"
echo "Database URL: postgresql://quotesdb:***@postgres-service.postgres.svc.cluster.local:5432/quotesdb"
SETUP_SCRIPT

# Copy PostgreSQL manifests to master
echo "Copying PostgreSQL manifests..."
scp -o StrictHostKeyChecking=no -r ../kubernetes/postgres/* ubuntu@${MASTER_IP}:~/

# Execute setup on master
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "./setup-postgres.sh"

# Apply all PostgreSQL manifests
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} <<'DEPLOY_POSTGRES'
# Apply ConfigMap
kubectl apply -f ~/configmap.yaml

# Apply StatefulSet
kubectl apply -f ~/statefulset.yaml

# Apply Services
kubectl apply -f ~/service.yaml

# Apply Backup CronJob
kubectl apply -f ~/backup-cronjob.yaml

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n postgres --timeout=300s

# Show status
kubectl get all -n postgres
kubectl get pvc -n postgres

echo ""
echo "PostgreSQL deployment completed!"
echo ""
echo "To connect from outside the cluster:"
echo "  1. Use port forwarding: kubectl port-forward -n postgres service/postgres-service 5432:5432"
echo "  2. Connect: psql -h localhost -U quotesdb -d quotesdb"
echo ""
echo "To run database migrations:"
echo "  kubectl run -it --rm migrate --image=quotesdb:latest --restart=Never -- npm run db:migrate"
DEPLOY_POSTGRES

echo ""
echo "PostgreSQL setup completed successfully!"
echo ""
echo "Database Password: $POSTGRES_PASSWORD"
echo ""
echo "IMPORTANT: Save this password securely! You'll need it for:"
echo "1. Database administration"
echo "2. Manual connections"
echo "3. Disaster recovery"
echo ""
echo "The application will automatically use the correct connection string."