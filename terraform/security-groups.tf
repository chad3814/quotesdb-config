# Security Group for Kubernetes Control Plane
resource "aws_security_group" "k8s_control_plane" {
  name_prefix = "${var.project_name}-${var.environment}-k8s-cp-"
  vpc_id      = aws_vpc.main.id

  # Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes API Server"
  }

  # etcd server client API
  ingress {
    from_port = 2379
    to_port   = 2380
    protocol  = "tcp"
    self      = true
    description = "etcd server client API"
  }

  # Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    self      = true
    description = "Kubelet API"
  }

  # kube-scheduler
  ingress {
    from_port = 10259
    to_port   = 10259
    protocol  = "tcp"
    self      = true
    description = "kube-scheduler"
  }

  # kube-controller-manager
  ingress {
    from_port = 10257
    to_port   = 10257
    protocol  = "tcp"
    self      = true
    description = "kube-controller-manager"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-k8s-control-plane-sg"
    Environment = var.environment
  }
}

# Security Group for Kubernetes Worker Nodes
resource "aws_security_group" "k8s_workers" {
  name_prefix = "${var.project_name}-${var.environment}-k8s-workers-"
  vpc_id      = aws_vpc.main.id

  # Kubelet API
  ingress {
    from_port = 10250
    to_port   = 10250
    protocol  = "tcp"
    security_groups = [aws_security_group.k8s_control_plane.id]
    description = "Kubelet API from control plane"
  }

  # NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort Services"
  }

  # Container network - Flannel VXLAN
  ingress {
    from_port = 8472
    to_port   = 8472
    protocol  = "udp"
    self      = true
    description = "Flannel VXLAN"
  }

  # Allow all traffic from control plane
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    security_groups = [aws_security_group.k8s_control_plane.id]
    description = "All TCP from control plane"
  }

  # Allow all traffic between workers
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "All TCP between workers"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_ips
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-k8s-workers-sg"
    Environment = var.environment
  }
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-sg"
    Environment = var.environment
  }
}