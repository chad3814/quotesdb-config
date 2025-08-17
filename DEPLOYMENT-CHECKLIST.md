# Deployment Checklist

This checklist ensures you have everything needed for a successful deployment.

## Pre-Deployment Requirements

### AWS Setup
- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] SSH Key Pair created in EC2 console (note the name)
- [ ] S3 bucket for Terraform state (optional but recommended)

### Local Tools
- [ ] Terraform installed (version >= 1.0)
- [ ] Docker installed and running
- [ ] kubectl installed
- [ ] Git configured with access to both repos

### OAuth Provider Setup (for Authentication)
- [ ] Google OAuth App created with correct redirect URLs
- [ ] GitHub OAuth App created with correct redirect URLs  
- [ ] Apple OAuth configured (optional)
- [ ] All OAuth credentials documented

### Repository Access
- [ ] quotesdb repository cloned
- [ ] quotesdb-config repository cloned
- [ ] Docker registry account (Docker Hub, ECR, etc.)

## Deployment Steps

### 1. Infrastructure (15-20 minutes)
- [ ] Copy terraform.tfvars.example to terraform.tfvars
- [ ] Edit terraform.tfvars with:
  - [ ] AWS region
  - [ ] Key pair name
  - [ ] Your IP for SSH access
  - [ ] Environment name
  - [ ] Instance types and counts
- [ ] Run `terraform init`
- [ ] Run `terraform plan` and review
- [ ] Run `terraform apply`
- [ ] Wait for EC2 instances to initialize
- [ ] Verify master IP: `terraform output k8s_master_public_ip`
- [ ] Test SSH access: `ssh ubuntu@$MASTER_IP`
- [ ] Verify cluster: `ssh ubuntu@$MASTER_IP "kubectl get nodes"`

### 2. Database Setup (5 minutes)
- [ ] Run PostgreSQL setup: `./scripts/setup-postgres-k8s.sh $MASTER_IP`
- [ ] **SAVE THE PASSWORD** displayed
- [ ] Verify database is running: `./scripts/postgres-operations.sh status $MASTER_IP`

### 3. Application Configuration (10 minutes)
- [ ] Copy kubernetes/secrets-template.yaml to kubernetes/secrets.yaml
- [ ] Edit kubernetes/secrets.yaml with:
  - [ ] NextAuth secret (generate with `openssl rand -base64 32`)
  - [ ] Google OAuth credentials
  - [ ] GitHub OAuth credentials
  - [ ] TMDB API key
  - [ ] Other OAuth providers (if used)
- [ ] Update kubernetes/configmap.yaml with your domain (if applicable)
- [ ] Update kubernetes/postgres/secret.yaml with the PostgreSQL password

### 4. Docker Image (5-10 minutes)
- [ ] Set registry: `export DOCKER_REGISTRY="docker.io/yourusername"`
- [ ] Build image: `docker build -t quotesdb:latest -f docker/Dockerfile ../quotesdb`
- [ ] Tag image: `docker tag quotesdb:latest $DOCKER_REGISTRY/quotesdb:latest`
- [ ] Push image: `docker push $DOCKER_REGISTRY/quotesdb:latest`

### 5. Application Deployment (5 minutes)
- [ ] Deploy: `./scripts/deploy-to-ec2-k8s.sh production latest $MASTER_IP`
- [ ] Check pods: `ssh ubuntu@$MASTER_IP "kubectl get pods -n quotesdb"`
- [ ] Check logs if needed: `ssh ubuntu@$MASTER_IP "kubectl logs -n quotesdb -l app=quotesdb"`
- [ ] Run migrations: `./scripts/postgres-operations.sh migrate $MASTER_IP`

### 6. Verification
- [ ] Get ALB URL: `terraform output alb_dns_name`
- [ ] Test application: `curl http://$ALB_DNS/api/health`
- [ ] Access in browser: `http://$ALB_DNS`
- [ ] Test OAuth login
- [ ] Create a test quote

### 7. Optional: Monitoring Setup
- [ ] Set up Kubernetes Dashboard: `./scripts/k8s-setup-dashboard.sh $MASTER_IP`
- [ ] Save dashboard token
- [ ] Configure backup to S3 (edit kubernetes/postgres/backup-cronjob.yaml)

## Post-Deployment

### DNS Setup (if using custom domain)
- [ ] Create Route53 hosted zone or use existing DNS provider
- [ ] Add CNAME record pointing to ALB DNS
- [ ] Update NEXTAUTH_URL in secrets
- [ ] Update OAuth redirect URLs

### SSL/TLS Setup
- [ ] Request ACM certificate for domain
- [ ] Add certificate ARN to terraform.tfvars
- [ ] Re-run terraform apply
- [ ] Update application URLs to use HTTPS

### Backup Verification
- [ ] Test manual backup: `./scripts/postgres-operations.sh backup $MASTER_IP`
- [ ] Verify backup exists
- [ ] Test restore process (in staging first!)

### Monitoring
- [ ] Set up CloudWatch alarms for EC2 instances
- [ ] Configure log aggregation (optional)
- [ ] Set up uptime monitoring

## Troubleshooting Quick Reference

### Cannot SSH to master
```bash
# Check security group allows your IP
# Verify key pair name in terraform.tfvars
# Check instance status in AWS console
```

### Kubernetes nodes not ready
```bash
ssh ubuntu@$MASTER_IP
sudo journalctl -u kubelet -f  # Check kubelet logs
kubectl describe nodes          # Check node issues
```

### Database connection failed
```bash
# Check PostgreSQL is running
kubectl get pods -n postgres
kubectl logs -n postgres postgres-0

# Test connection
kubectl run -it --rm debug --image=postgres:16-alpine --restart=Never \
  -- psql postgresql://quotesdb:password@postgres-service.postgres:5432/quotesdb
```

### Application not accessible
```bash
# Check ALB target health in AWS console
# Verify NodePort service is running
kubectl get svc -n quotesdb
# Check application logs
kubectl logs -n quotesdb -l app=quotesdb
```

## Cleanup

To destroy all resources:
```bash
cd terraform
terraform destroy
# Type 'yes' to confirm
```

Note: This will delete ALL resources including the database. Back up data first!