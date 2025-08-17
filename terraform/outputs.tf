output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID of the VPC"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "IDs of public subnets"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "IDs of private subnets"
}

output "k8s_cluster_endpoint" {
  value       = "https://${aws_eip.k8s_master.public_ip}:6443"
  description = "Kubernetes API server endpoint"
}

output "k8s_ssh_command" {
  value       = "ssh ubuntu@${aws_eip.k8s_master.public_ip}"
  description = "SSH command to connect to Kubernetes master"
}

output "k8s_worker_count" {
  value       = var.worker_count
  description = "Number of worker nodes"
}

output "application_url" {
  value       = var.acm_certificate_arn != "" ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
  description = "Application URL via load balancer"
}

output "deployment_commands" {
  value = <<-EOT
    # Deploy application:
    ./scripts/deploy-to-ec2-k8s.sh ${var.environment} latest ${aws_eip.k8s_master.public_ip}
    
    # Setup Kubernetes Dashboard:
    ./scripts/k8s-setup-dashboard.sh ${aws_eip.k8s_master.public_ip}
    
    # Connect to master:
    ssh ubuntu@${aws_eip.k8s_master.public_ip}
    
    # Get kubeconfig:
    scp ubuntu@${aws_eip.k8s_master.public_ip}:~/.kube/config ./kubeconfig
    export KUBECONFIG=./kubeconfig
  EOT
  description = "Useful commands for managing the deployment"
}