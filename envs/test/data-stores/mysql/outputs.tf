output "db_instance_address" {
  value = aws_db_instance.test_db.address
  description = "The address of the MySQL instance"
}

output "db_instance_port" {
  value = aws_db_instance.test_db.port
  description = "The port of the MySQL instance"
}