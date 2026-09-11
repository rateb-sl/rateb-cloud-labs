resource "aws_lb" "web" {
  name               = "${var.project_name}-web-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [var.alb_security_group_id]
  subnets         = var.subnet_ids

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-web-alb"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }

  tags = {
    Name        = "${var.project_name}-web-target-group"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "dev"
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn = aws_lb_target_group.web.arn
      }
    }
  }

  tags = {
    Name        = "${var.project_name}-web-listener"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "dev"
  }
}