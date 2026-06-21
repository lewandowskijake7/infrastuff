## OUTPUTS
# output "public_ip" {
#   value = aws_instance.example.public_ip
#   description = "The public IP address of the web server"
# }
output "alb_dns_name" {
  value = aws_lb.test_lb.dns_name
  description = "The DNS name of the ALB"
}

output "subnet_list" {
  value = data.aws_subnets.default.ids
  description = "The DNS name of the ALB"
}