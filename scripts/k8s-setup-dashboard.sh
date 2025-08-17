#!/bin/bash

# Script to set up Kubernetes Dashboard and monitoring
set -e

MASTER_IP=$1

if [ -z "$MASTER_IP" ]; then
    echo "Usage: $0 <master-ip>"
    exit 1
fi

echo "Setting up Kubernetes Dashboard on master node..."

# Create setup script
cat <<'SETUP_SCRIPT' | ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "cat > ~/setup-dashboard.sh && chmod +x ~/setup-dashboard.sh"
#!/bin/bash
set -e

# Install Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create admin user for dashboard
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Install metrics server for resource monitoring
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics server for self-signed certificates (for development)
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

echo "Dashboard setup complete!"
echo ""
echo "To get the admin token, run:"
echo "kubectl -n kubernetes-dashboard create token admin-user"
echo ""
echo "To access the dashboard:"
echo "1. Start proxy: kubectl proxy"
echo "2. Access: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
SETUP_SCRIPT

# Execute setup on master
ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "./setup-dashboard.sh"

# Get admin token
echo ""
echo "Getting admin token for dashboard access..."
TOKEN=$(ssh -o StrictHostKeyChecking=no ubuntu@${MASTER_IP} "kubectl -n kubernetes-dashboard create token admin-user")
echo ""
echo "==================================="
echo "Dashboard Admin Token:"
echo "$TOKEN"
echo "==================================="
echo ""
echo "To access the dashboard:"
echo "1. Set up SSH tunnel: ssh -L 8001:localhost:8001 ubuntu@${MASTER_IP}"
echo "2. Run kubectl proxy on the master"
echo "3. Access: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
echo "4. Use the token above to login"