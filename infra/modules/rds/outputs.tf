output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "password" {
  value     = aws_db_instance.this.password
  sensitive = true
}

output "security_group_id" {
  value = aws_security_group.rds.id
}

