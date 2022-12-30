terraform {
  # Terraform 버전 지정 
  required_version = ">= 1.0.0, < 2.0.0"
  #공급자 지정
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

# Launch template
resource "aws_launch_template" "example" {
  name                   = "std07-example"
  image_id               = "ami-06eea3cd85e2db8ce" # Ubuntu 20.04 
  instance_type          = "t2.micro"
  key_name               = "std07-key"
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(data.template_file.web_output.rendered)


  lifecycle {
    create_before_destroy = true
  }
}

# Autoscaling Group
resource "aws_autoscaling_group" "example" {
  availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]
  name               = "std07-terraform-asg-example"
  desired_capacity   = 1
  min_size           = 1
  max_size           = 2


  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"


  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }


  tag {
    key                 = "Name"
    value               = "std07-terraform-asg-example"
    propagate_at_launch = true
  }
}


#Load Balancer
resource "aws_lb" "example" {
  name               = "std07-terraform-asg-example"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}


#Target Group
resource "aws_lb_target_group" "asg" {
  name     = "std07-terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id


  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}


#LoadBalancer Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}


#Load Balancer listener rules
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




#Instance Security Group, 80 open
resource "aws_security_group" "alb" {
  name = "std07-terraform-exmaple-alb"

  #inbound HTTP traffic allow
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #all outbound traffic allow
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



resource "aws_security_group" "instance" {
  name = var.security_group_name

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "template_file" "web_output" {
  template = file("${path.module}/web.sh")
  vars = {
    server_port = "${var.server_port}"
  }
}








