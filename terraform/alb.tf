# Application Load Balancer for Kubernetes Services
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = aws_subnet.public[*].id

  enable_deletion_protection = var.environment == "production"
  enable_http2              = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name                                         = "${var.project_name}-${var.environment}-alb"
    Environment                                  = var.environment
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Target Group for Kubernetes NodePort Services
resource "aws_lb_target_group" "k8s_http" {
  name     = "${var.project_name}-${var.environment}-k8s-http"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/api/health"
    matcher             = "200"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-k8s-http-tg"
    Environment = var.environment
  }
}

# Attach Worker Nodes to Target Group
resource "aws_lb_target_group_attachment" "k8s_workers" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.k8s_http.arn
  target_id        = aws_instance.k8s_workers[count.index].id
  port             = 30080
}

# HTTP Listener with redirect to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS Listener (requires ACM certificate)
resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0
  
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_http.arn
  }
}

# Output ALB DNS
output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "alb_zone_id" {
  value       = aws_lb.main.zone_id
  description = "Zone ID of the Application Load Balancer"
}