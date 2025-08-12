terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  student_suffix = substr(var.student_number, length(var.student_number) - 4, 4)
  name_prefix = "${var.student_name}-${local.student_suffix}"
}

module "network" {
  source = "./modules/vpc"

  name_prefix = "${local.name_prefix}"
  cidr_block  = var.vpc_cidr

  availability_zones = length(var.azs) > 0 ? var.azs : []
  public_subnet_bits = var.public_subnet_bits
  private_subnet_bits = var.private_subnet_bits
  enable_nat_gateway = var.enable_nat_gateway
}

# S3 for static files
resource "aws_s3_bucket" "static" {
  bucket = var.s3_bucket_name
  acl    = "private"

  tags = {
    Name = "${local.name_prefix}-s3-staging"
  }
}

# Security group for ALB
resource "aws_security_group" "alb_sg" {
  name   = "${local.name_prefix}-alb-sg-staging"
  vpc_id = module.network.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# Security group for EC2 instances (allow from ALB)
resource "aws_security_group" "ec2_sg" {
  name   = "${local.name_prefix}-ec2-sg-staging"
  vpc_id = module.network.vpc_id

  ingress {
    description = "Allow from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ec2-sg" }
}

# ALB
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb-staging"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.network.public_subnet_ids

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "${local.name_prefix}-tg-staging"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id

  health_check {
    matcher  = "200"
    path     = "/"
    interval = 30
    timeout  = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.name_prefix}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# EC2 instances in private subnets
resource "aws_instance" "web" {
  count         = length(module.network.private_subnet_ids)
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = element(module.network.private_subnet_ids, count.index)
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx
              systemctl enable nginx
              systemctl start nginx
              echo "Hello from ${local.name_prefix} - $(hostname)" > /var/www/html/index.html
              EOF

  tags = { Name = "${local.name_prefix}-web-${count.index}" }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_lb_target_group_attachment" "web" {
  for_each = { for idx, inst in aws_instance.web : idx => inst }

  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = each.value.id
  port             = 80
}

# RDS Subnet group
resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = module.network.private_subnet_ids
  tags = { Name = "${local.name_prefix}-db-subnet-group" }
}

# Aurora DB cluster (serverless would be more complex; use small cluster)
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "${local.name_prefix}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = "13.6"
  database_name      = "analytics"
  master_username    = "adminuser"
  master_password    = random_password.db_password.result

  db_subnet_group_name = aws_db_subnet_group.aurora.name
  skip_final_snapshot  = true
  backup_retention_period = 1
  tags = { Name = "${local.name_prefix}-aurora" }
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = 2
  identifier         = "${local.name_prefix}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t3.small"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  publicly_accessible = false
  tags = { Name = "${local.name_prefix}-aurora-${count.index}" }
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

# CloudWatch alarm for EC2 CPU >75%
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-ec2-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Triggered when average CPU > 75% across instances"
  dimensions = {
    AutoScalingGroupName = ""
  }
  alarm_actions = []
}

