provider "aws" {
  region = "us-east-2"
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

data "terraform_remote_state" "db" {
  backend = "s3"
  config = {
    bucket = "jlew-terraform-state-example"
    key = "test/data-stores/mysql/terraform.tfstate"
    region = "us-east-2"
  }
}

resource "aws_launch_template" "test_launch_template" {
  image_id = "ami-0ea1cddefe0c4aed5"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.test_sg.id]
  user_data = base64encode(templatefile("scripts/user-data.sh", {
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.db_instance_address
    db_port = data.terraform_remote_state.db.outputs.db_instance_port
  }))
  # This is needed because the typical Terraform flow is to destroy the old resource and then create the new one.
  # The destruction of the old resource fails because the ASG is still referencing that resource.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "test_asg" {
  launch_template {
    id      = aws_launch_template.test_launch_template.id
    version = "$Latest"
  }
  min_size = 2
  max_size = 10
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.test_lb_target_group.arn]
  health_check_type = "ELB"

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

# LOAD BALANCERS

resource "aws_lb" "test_lb" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.test_alb_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.test_lb.arn
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

resource "aws_lb_listener_rule" "test_lb_listener_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority = 10

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.test_lb_target_group.arn
  }
}

resource "aws_lb_target_group" "test_lb_target_group" {
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
resource "aws_security_group" "test_sg" {
  name = "terraform-example-sg"
  description = "open ${var.server_port} port to world"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "test_alb_sg" {
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
  security_group_id = aws_security_group.test_sg.id
}

terraform {
    backend "s3" {
        key = "test/services/webserver-cluster/terraform.tfstate"
    }
}