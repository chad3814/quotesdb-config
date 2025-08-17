# QuotesDB Configuration & Deployment

This repository contains the deployment configuration and infrastructure code for the QuotesDB application.

## Repository Structure

```
quotesdb-config/
├── .github/workflows/      # GitHub Actions workflows
│   ├── deploy.yml          # Main deployment workflow
│   └── pr-environment.yml  # PR environment management
├── docker/                 # Docker configuration
│   ├── Dockerfile          # Multi-stage Docker build
│   └── docker-compose.yml  # Local development setup
├── kubernetes/             # Kubernetes manifests
│   ├── namespace.yaml      # Namespace definition
│   ├── deployment.yaml     # Application deployment
│   ├── service.yaml        # Service definitions
│   ├── ingress.yaml        # Ingress configuration
│   ├── configmap.yaml      # Configuration values
│   ├── secrets-template.yaml # Secret template
│   └── postgres/           # PostgreSQL on Kubernetes
│       ├── namespace.yaml  # Database namespace
│       ├── statefulset.yaml # PostgreSQL StatefulSet
│       ├── service.yaml    # Database services
│       ├── configmap.yaml  # PostgreSQL config
│       ├── secret.yaml     # Database credentials
│       ├── storage-class.yaml # EBS storage class
│       ├── backup-cronjob.yaml # Automated backups
│       └── restore-job.yaml # Restore template
├── scripts/                # Deployment scripts
│   ├── deploy-to-ec2-k8s.sh      # Deploy to K8s on EC2
│   ├── setup-postgres-k8s.sh     # PostgreSQL setup
│   ├── postgres-operations.sh    # Database operations
│   ├── k8s-setup-dashboard.sh    # Dashboard setup
│   ├── setup-pr-environment.sh   # PR environment setup
│   └── cleanup-pr-environment.sh # PR environment cleanup
└── terraform/              # Infrastructure as Code
    ├── main.tf             # Terraform main configuration
    ├── variables.tf        # Variable definitions
    ├── vpc.tf              # Network configuration
    ├── security-groups.tf  # Security groups
    ├── ec2-k8s.tf          # Kubernetes on EC2
    ├── alb.tf              # Load balancer
    └── outputs.tf          # Terraform outputs
```

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Terraform (>= 1.0)
- AWS CLI configured with credentials
- SSH key pair in AWS for EC2 access (create one in EC2 console if needed)
- kubectl (will be configured after setup)
- An AWS account with permissions to create EC2, VPC, and EBS resources

### Local Development

1. Clone both repositories:
```bash
git clone https://github.com/your-username/quotesdb.git
git clone https://github.com/your-username/quotesdb-config.git
```

2. Start local environment:
```bash
cd quotesdb-config/docker
docker-compose up -d
```

3. Run database migrations:
```bash
docker-compose exec app npm run db:migrate
```

### Deployment

#### 1. Infrastructure Setup

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
#   - Set your AWS region
#   - Add your SSH key pair name
#   - Update ssh_allowed_ips with your IP address
#   - Adjust instance types and counts as needed

terraform init
terraform plan
terraform apply

# Wait for infrastructure to be ready (5-10 minutes)
# Get outputs
MASTER_IP=$(terraform output -raw k8s_master_public_ip)
ALB_DNS=$(terraform output -raw alb_dns_name)

# Verify cluster is ready
ssh ubuntu@$MASTER_IP "kubectl get nodes"
```

#### 2. Database Setup

```bash
# Deploy PostgreSQL to the cluster
./scripts/setup-postgres-k8s.sh $MASTER_IP
# Save the generated password!
```

#### 3. Application Deployment

```bash
# First, update the OAuth secrets in kubernetes/secrets-template.yaml
cp kubernetes/secrets-template.yaml kubernetes/secrets.yaml
# Edit kubernetes/secrets.yaml with your OAuth credentials

# Build and push your Docker image (adjust registry as needed)
export DOCKER_REGISTRY="docker.io/yourusername"  # or your ECR URL
docker build -t quotesdb:latest -f docker/Dockerfile ../quotesdb
docker tag quotesdb:latest $DOCKER_REGISTRY/quotesdb:latest
docker push $DOCKER_REGISTRY/quotesdb:latest

# Deploy the application
./scripts/deploy-to-ec2-k8s.sh production latest $MASTER_IP

# Verify deployment
ssh ubuntu@$MASTER_IP "kubectl get pods -n quotesdb"

# Access the application
echo "Application available at: http://$ALB_DNS"
```

#### Automated Deployment (GitOps)

Push to branches:
- `develop` → Deploys to staging
- `main` → Deploys to production

#### PR Environments

PR environments are automatically created when you open a pull request:

1. Open a PR in the main quotesdb repository
2. The GitHub Action will:
   - Create a database branch from staging
   - Deploy the PR code to a temporary environment
   - Comment on the PR with the environment URL

Cleanup happens automatically when the PR is closed.

### Manual PR Environment Management

Create PR environment:
```bash
./scripts/setup-pr-environment.sh 123
```

Cleanup PR environment:
```bash
./scripts/cleanup-pr-environment.sh 123
```

## Configuration

### Required Secrets

Create the following secrets in your Kubernetes cluster or CI/CD platform:

#### GitHub Secrets (for Actions)
- `PRODUCTION_DATABASE_URL`
- `STAGING_DATABASE_URL`
- `TMDB_API_KEY`
- `GITOPS_TOKEN`
- `DOCKER_REGISTRY_TOKEN`

#### Kubernetes Secrets
Copy and modify the template:
```bash
cp kubernetes/secrets-template.yaml kubernetes/secrets.yaml
# Edit secrets.yaml with actual values
kubectl apply -f kubernetes/secrets.yaml
```

### Environment Variables

The application requires these environment variables:

- `DATABASE_URL` - PostgreSQL connection string
- `NEXTAUTH_URL` - Application URL
- `NEXTAUTH_SECRET` - NextAuth secret key
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
- `GITHUB_CLIENT_ID` - GitHub OAuth client ID
- `GITHUB_CLIENT_SECRET` - GitHub OAuth client secret
- `APPLE_CLIENT_ID` - Apple OAuth client ID
- `APPLE_CLIENT_SECRET` - Apple OAuth client secret
- `TMDB_API_KEY` - The Movie Database API key

## Infrastructure

### Self-Managed Kubernetes on EC2

The infrastructure runs a self-managed Kubernetes cluster on EC2 instances:

- **Control Plane**: Single master node (t3.medium by default)
- **Worker Nodes**: Configurable count (2 by default)
- **Database**: PostgreSQL runs as a StatefulSet on the cluster
- **Storage**: EBS volumes with automatic provisioning
- **Load Balancer**: AWS ALB for external access

### Kubernetes Access

```bash
# Get kubeconfig from master
scp ubuntu@$MASTER_IP:~/.kube/config ./kubeconfig
export KUBECONFIG=./kubeconfig

# Check cluster status
kubectl get nodes
kubectl get all --all-namespaces

# Set up Kubernetes Dashboard (optional)
./scripts/k8s-setup-dashboard.sh $MASTER_IP
# Save the token that's displayed!

# Access dashboard via SSH tunnel
ssh -L 8001:localhost:8001 ubuntu@$MASTER_IP
# In another terminal: kubectl proxy
# Browse to: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

### Database Management

#### PostgreSQL on Kubernetes

The database runs as a StatefulSet with:
- Persistent EBS volumes
- Automated daily backups
- Point-in-time recovery capability

#### Database Operations

```bash
# Manual backup
./scripts/postgres-operations.sh backup $MASTER_IP

# Restore from backup
./scripts/postgres-operations.sh restore $MASTER_IP /backup/file.sql.gz

# Open PostgreSQL shell
./scripts/postgres-operations.sh shell $MASTER_IP

# Check database status
./scripts/postgres-operations.sh status $MASTER_IP

# View logs
./scripts/postgres-operations.sh logs $MASTER_IP

# Run migrations
./scripts/postgres-operations.sh migrate $MASTER_IP
```

## Monitoring

### Health Checks
- Liveness probe: `/api/health`
- Readiness probe: `/api/health`
- Check interval: 10 seconds

### Logs
Application logs are available via:
```bash
kubectl logs -n quotesdb -l app=quotesdb --tail=100 -f
```

## Security

### Best Practices
1. Never commit secrets to version control
2. Use separate OAuth apps for each environment
3. Rotate secrets regularly
4. Use network policies in Kubernetes
5. Enable SSL/TLS for all endpoints

### Secret Management
- Use Kubernetes secrets for runtime configuration
- Store sensitive values in GitHub Secrets for CI/CD
- Consider using HashiCorp Vault or AWS Secrets Manager for production

## Complete Setup Example

Here's a complete example from scratch:

```bash
# 1. Clone the config repo
git clone https://github.com/your-username/quotesdb-config.git
cd quotesdb-config

# 2. Set up Terraform variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Add your settings

# 3. Deploy infrastructure
terraform init
terraform apply -auto-approve

# 4. Get connection details
MASTER_IP=$(terraform output -raw k8s_master_public_ip)
echo "Master IP: $MASTER_IP"

# 5. Set up PostgreSQL
cd ..
./scripts/setup-postgres-k8s.sh $MASTER_IP
# IMPORTANT: Save the password shown!

# 6. Configure application secrets
cp kubernetes/secrets-template.yaml kubernetes/secrets.yaml
vim kubernetes/secrets.yaml  # Add OAuth credentials

# 7. Deploy application
export DOCKER_REGISTRY="docker.io/yourusername"
./scripts/deploy-to-ec2-k8s.sh production latest $MASTER_IP

# 8. Access the application
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)
echo "Application URL: http://$ALB_DNS"
```

## Troubleshooting

### Common Issues

#### Deployment Failed
```bash
# Check deployment status
kubectl get deployments -n quotesdb
kubectl describe deployment quotesdb -n quotesdb

# Check pod logs
kubectl logs -n quotesdb -l app=quotesdb --tail=50
```

#### Database Connection Issues
```bash
# Test database connectivity
kubectl run -it --rm debug --image=postgres:16-alpine --restart=Never -- psql $DATABASE_URL
```

#### PR Environment Not Created
```bash
# Check GitHub Action logs
# Manually create if needed
./scripts/setup-pr-environment.sh <PR_NUMBER>
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally with Docker Compose
5. Submit a pull request

## License

MIT License - see LICENSE file for details