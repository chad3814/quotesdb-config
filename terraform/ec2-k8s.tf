# IAM Role for Kubernetes Nodes
resource "aws_iam_role" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-k8s-node-role"
    Environment = var.environment
  }
}

# IAM Role Policy for Kubernetes Nodes
resource "aws_iam_role_policy" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node-policy"
  role = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeVpcs",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
          "iam:CreateServiceLinkedRole",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile for Kubernetes Nodes
resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.project_name}-${var.environment}-k8s-node-profile"
  role = aws_iam_role.k8s_node.name
}

# User data script for Kubernetes Control Plane
locals {
  master_userdata = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install Docker
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Configure containerd
    cat <<EOT > /etc/containerd/config.toml
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true
    EOT
    systemctl restart containerd
    
    # Install Kubernetes components
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    cat <<EOT > /etc/apt/sources.list.d/kubernetes.list
    deb https://apt.kubernetes.io/ kubernetes-xenial main
    EOT
    apt-get update
    apt-get install -y kubelet=1.28.* kubeadm=1.28.* kubectl=1.28.*
    apt-mark hold kubelet kubeadm kubectl
    
    # Enable kernel modules
    modprobe br_netfilter
    modprobe overlay
    
    # Set up required sysctl params
    cat <<EOT > /etc/sysctl.d/99-kubernetes-cri.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    EOT
    sysctl --system
    
    # Initialize Kubernetes control plane
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    
    kubeadm init \
      --apiserver-advertise-address=$PRIVATE_IP \
      --apiserver-cert-extra-sans=$PUBLIC_IP \
      --pod-network-cidr=10.244.0.0/16 \
      --service-cidr=10.96.0.0/12
    
    # Configure kubectl for root user
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config
    
    # Configure kubectl for ubuntu user
    mkdir -p /home/ubuntu/.kube
    cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
    chown ubuntu:ubuntu /home/ubuntu/.kube/config
    
    # Install Flannel network plugin
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    
    # Install NGINX Ingress Controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/aws/deploy.yaml
    
    # Install AWS EBS CSI Driver for persistent volumes
    kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
    
    # Generate join command for workers
    kubeadm token create --print-join-command > /tmp/join-command.sh
    
    # Store join command in AWS Systems Manager Parameter Store
    aws ssm put-parameter \
      --name "/${var.project_name}/${var.environment}/k8s-join-command" \
      --value "$(cat /tmp/join-command.sh)" \
      --type "SecureString" \
      --overwrite \
      --region ${var.aws_region}
    
    # Label the node
    kubectl label node $(hostname) node-role.kubernetes.io/control-plane=true
    
    # Allow scheduling on control plane (for small clusters)
    if [ "${var.worker_count}" -eq "0" ]; then
      kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    fi
  EOF

  worker_userdata = <<-EOF
    #!/bin/bash
    set -e
    
    # Update system
    apt-get update
    apt-get upgrade -y
    
    # Install Docker
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Configure containerd
    cat <<EOT > /etc/containerd/config.toml
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true
    EOT
    systemctl restart containerd
    
    # Install Kubernetes components
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    cat <<EOT > /etc/apt/sources.list.d/kubernetes.list
    deb https://apt.kubernetes.io/ kubernetes-xenial main
    EOT
    apt-get update
    apt-get install -y kubelet=1.28.* kubeadm=1.28.* kubectl=1.28.*
    apt-mark hold kubelet kubeadm kubectl
    
    # Enable kernel modules
    modprobe br_netfilter
    modprobe overlay
    
    # Set up required sysctl params
    cat <<EOT > /etc/sysctl.d/99-kubernetes-cri.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    EOT
    sysctl --system
    
    # Wait for control plane to be ready and get join command
    apt-get install -y awscli
    sleep 60
    
    # Retrieve join command from Parameter Store
    JOIN_COMMAND=$(aws ssm get-parameter \
      --name "/${var.project_name}/${var.environment}/k8s-join-command" \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text \
      --region ${var.aws_region})
    
    # Join the cluster
    eval $JOIN_COMMAND
  EOF
}

# EC2 Instance for Kubernetes Control Plane
resource "aws_instance" "k8s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name              = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_control_plane.id]
  subnet_id             = aws_subnet.public[0].id
  iam_instance_profile  = aws_iam_instance_profile.k8s_node.name
  
  user_data = base64encode(local.master_userdata)
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }
  
  tags = {
    Name                                         = "${var.project_name}-${var.environment}-k8s-master"
    Environment                                  = var.environment
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                         = "control-plane"
  }
}

# EC2 Instances for Kubernetes Worker Nodes
resource "aws_instance" "k8s_workers" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name              = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_workers.id]
  subnet_id             = aws_subnet.private[count.index % length(aws_subnet.private)].id
  iam_instance_profile  = aws_iam_instance_profile.k8s_node.name
  
  user_data = base64encode(local.worker_userdata)
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }
  
  depends_on = [aws_instance.k8s_master]
  
  tags = {
    Name                                         = "${var.project_name}-${var.environment}-k8s-worker-${count.index + 1}"
    Environment                                  = var.environment
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    Role                                         = "worker"
  }
}

# Elastic IP for Control Plane
resource "aws_eip" "k8s_master" {
  instance = aws_instance.k8s_master.id
  domain   = "vpc"
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-k8s-master-eip"
    Environment = var.environment
  }
}

# Outputs
output "k8s_master_public_ip" {
  value       = aws_eip.k8s_master.public_ip
  description = "Public IP of Kubernetes control plane"
}

output "k8s_master_private_ip" {
  value       = aws_instance.k8s_master.private_ip
  description = "Private IP of Kubernetes control plane"
}

output "k8s_worker_private_ips" {
  value       = aws_instance.k8s_workers[*].private_ip
  description = "Private IPs of Kubernetes worker nodes"
}