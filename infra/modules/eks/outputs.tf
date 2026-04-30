output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_auth_token" {
  value     = data.aws_eks_cluster_auth.this.token
  sensitive = true
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

