terraform {
  backend "s3" {
    bucket         = "my-terraform-state-andrii"
    key            = "prod/infra/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.81.0"
    }
  }
}
provider "aws" {
  region = "us-east-2"
}

resource "aws_launch_template" "example" {
  name_prefix   = "terraform-example-"
  image_id      = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "Hello, World" > index.html
    nohup busybox httpd -f -p ${var.server_port} &
  EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "terraform-asg-example"
    }
  }
}

resource "aws_autoscaling_group" "example" {
  min_size             = 2
  max_size             = 10
  desired_capacity     = 2
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.asg.arn]
  health_check_type    = "ELB"

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}


#We can send any request to 8080 port
resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EXAMPLE
variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}

data "aws_vpc" "default" {
default = true
}

data "aws_subnets" "default" {
filter {
name = "vpc-id"
values = [data.aws_vpc.default.id]
}
}



resource "aws_lb" "example" {
name = "terraform-asg-example"
load_balancer_type = "application"
subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
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

resource "aws_security_group" "alb" {
name = "terraform-example-alb"
# Allow all income
ingress {
from_port = 80
to_port = 80
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
# Allow all outcome
egress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
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
interval = 15
  timeout = 3
healthy_threshold = 2
unhealthy_threshold = 2
}
}

# collect all together
resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
  path_pattern {
    values = ["*"]
  }
}

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

output "alb_dns_name" {
value = aws_lb.example.dns_name
description = "The domain name of the load balancer"
}