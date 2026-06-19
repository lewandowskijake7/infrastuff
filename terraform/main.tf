provider "aws" {
  region = "us-east-2"
}

## VARIABLES
variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

## DATA SOURCES
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

## OUTPUTS
# output "public_ip" {
#   value = aws_instance.example.public_ip
#   description = "The public IP address of the web server"
# }
output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The DNS name of the ALB"
}

# resource "aws_instance" "example" {
#   ami           = "ami-0ea1cddefe0c4aed5"
#   instance_type = "t2.micro"
#   vpc_security_group_ids = [aws_security_group.example-sg.id]

#   user_data = <<-EOF
#               #!/bin/bash
#               echo "Yo, what's up?" > index.html
#               nohup busybox httpd -f -p ${var.server_port} &
#               EOF

#   user_data_replace_on_change = true

#   tags = {
#     Name = "terraform-example"
#   }
# }

resource "aws_launch_template" "example" {
  image_id = "ami-0ea1cddefe0c4aed5"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.example-sg.id]
  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Yo, what's up?" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
              )
  # This is needed because the typical Terraform flow is to destroy the old resource and then create the new one.
  # The destruction of the old resource fails because the ASG is still referencing that resource.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }
  min_size = 2
  max_size = 10
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

# LOAD BALANCERS

resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 10

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 10
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

# SECURITY GROUPS
resource "aws_security_group" "example-sg" {
  name = "terraform-example-sg"
  description = "open ${var.server_port} port to world"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_sg" {
  name = "terraform-alb-sg"
  description = "allow HTTP traffic to the ALB"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.example-sg.id
}