provider "aws" {
  region = "us-east-2"
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

# Security groups for Load Balancer, ECS and EC2 postgres --------------------------

resource "aws_security_group" "alb_sg" {
  name = "abhishekharkar-strapi-alb-sg"
  description = "Allow HTTP access"
  vpc_id = data.aws_vpc.default.id

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

resource "aws_security_group" "ecs_sg" {
  name = "abhishekharkar-ecs-sg"
  description = "Allow ALB to reach ECS"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 1337
    to_port = 1337
    protocol = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "postgres_sg" {
  name = "abhishekharkar-postgres-sg"
  description = "Allow ECS to reach postgres db"
  vpc_id = data.aws_vpc.default.id

  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  ingress {
    from_port = 22
    to_port = 22
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

# Application Load Balancer --------------------------------------------------------

resource "aws_lb" "strapi_alb" {
  name = "abhishekharkar-strapi-alb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.alb_sg.id]
  subnets = [
    "subnet-0f768008c6324831f",
    "subnet-0cc2ddb32492bcc41"
  ]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "strapi_tg" {
  name = "abhishekharkar-strapi-tg"
  port = 1337
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
    matcher = "200-399"
  }

  target_type = "ip"
}

resource "aws_lb_listener" "strapi_listener" {
  load_balancer_arn = aws_lb.strapi_alb.arn
  port = 80
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.strapi_tg.arn
  }
}

output "alb_url" {
  value = aws_lb.strapi_alb.dns_name
}

# ECS ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "strapi_cluster" {
  name = "abhishekharkar-strapi-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "strapi" {
  family = "abhishekharkar-strapi-task"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = "512"
  memory = "1024"
  execution_role_arn = var.ecs_executation_role

  container_definitions = templatefile("${path.module}/ecs_container_definitions.tmpl", {
    HOST = "0.0.0.0"
    PORT = "1337"
    ecr_image = var.ecr_image
    APP_KEYS = var.APP_KEYS
    API_TOKEN_SALT = var.API_TOKEN_SALT
    ADMIN_JWT_SECRET = var.ADMIN_JWT_SECRET
    TRANSFER_TOKEN_SALT = var.TRANSFER_TOKEN_SALT
    ENCRYPTION_KEY = var.ENCRYPTION_KEY
    JWT_SECRET = var.JWT_SECRET
    DATABASE_CLIENT = "postgres"
    DATABASE_HOST = aws_instance.postgres_ec2.private_ip
    DATABASE_PORT = "5432"
    DATABASE_NAME = var.DATABASE_NAME
    DATABASE_USERNAME = var.DATABASE_USERNAME
    DATABASE_PASSWORD = var.DATABASE_PASSWORD
    DATABASE_SSL = "false"
  })

  depends_on = [aws_cloudwatch_log_group.strapi]
}

resource "aws_ecs_service" "strapi" {
  name = "abhishekharkar-strapi-service"
  cluster = aws_ecs_cluster.strapi_cluster.id
  launch_type = "FARGATE"
  task_definition = aws_ecs_task_definition.strapi.arn
  desired_count = 1

  network_configuration {
    subnets = [
      "subnet-0f768008c6324831f",
      "subnet-0cc2ddb32492bcc41"
    ]
    assign_public_ip = true
    security_groups = [aws_security_group.ecs_sg.id]
  }

  depends_on = [
    aws_instance.postgres_ec2,
    aws_lb.strapi_alb,
    aws_lb_target_group.strapi_tg,
    aws_lb_listener.strapi_listener
  ]

  load_balancer {
    target_group_arn = aws_lb_target_group.strapi_tg.arn
    container_name = "strapi"
    container_port = 1337
  }
}

# EC2 postgres database ------------------------------------------------------------

resource "aws_instance" "postgres_ec2" {
  ami = "ami-0d1b5a8c13042c939" 
  instance_type = "t3.micro"
  subnet_id = "subnet-0f768008c6324831f"
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]

  user_data = templatefile("${path.module}/../User_data2.sh", {
    DATABASE_NAME = var.DATABASE_NAME
    DATABASE_USERNAME = var.DATABASE_USERNAME
    DATABASE_PASSWORD = var.DATABASE_PASSWORD
  })

  tags = {
    Name = "abhishekharkar-strapi"
  }
}

# Cloudwatch Logs and Metrics ----------------------------------------------------- 

resource "aws_cloudwatch_log_group" "strapi" {
  name              = "/ecs/abhishekharkar-strapi"
  retention_in_days = 7
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "abhishekharkar-HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 70

  dimensions = {
    ClusterName = aws_ecs_cluster.strapi_cluster.name
    ServiceName = aws_ecs_service.strapi.name
  }

  alarm_description = "Alarm when ECS service CPU exceeds 70%"
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "abhishekharkar-HighMemoryUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 75

  dimensions = {
    ClusterName = aws_ecs_cluster.strapi_cluster.name
    ServiceName = aws_ecs_service.strapi.name
  }

  alarm_description = "Alarm when ECS service memory exceeds 75%"
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_tasks" {
  alarm_name          = "abhishekharkar-UnhealthyTaskCount"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    LoadBalancer = aws_lb.strapi_alb.dns_name
    TargetGroup  = aws_lb_target_group.strapi_tg.arn_suffix
  }

  alarm_description = "Alarm when ECS tasks are unhealthy (via ALB)"
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "abhishekharkar-HighLatency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2.0

  dimensions = {
    LoadBalancer = aws_lb.strapi_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.strapi_tg.arn_suffix
  }

  alarm_description = "Alarm when application latency exceeds 2 seconds"
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_dashboard" "strapi_dashboard" {
  dashboard_name = "abhishekharkar-Strapi-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x    = 0,
        y    = 0,
        width = 12,
        height = 6,
        properties = {
          title = "CPU Utilization",
          view = "timeSeries",
          region = "us-east-2",
          metrics = [
            [ "AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.strapi_cluster.name, "ServiceName", aws_ecs_service.strapi.name ]
          ],
          period = 60,
          stat   = "Average"
        }
      },
      {
        type = "metric",
        x    = 12,
        y    = 0,
        width = 12,
        height = 6,
        properties = {
          title = "Memory Utilization",
          view = "timeSeries",
          region = "us-east-2",
          metrics = [
            [ "AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.strapi_cluster.name, "ServiceName", aws_ecs_service.strapi.name ]
          ],
          period = 60,
          stat   = "Average"
        }
      },
      {
        type = "metric",
        x    = 12,
        y    = 6,
        width = 12,
        height = 6,
        properties = {
          title = "Network I/O (Container Insights)",
          view = "timeSeries",
          region = "us-east-2",
          metrics = [
            [ "ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", aws_ecs_cluster.strapi_cluster.name, "ServiceName", aws_ecs_service.strapi.name ],
            [ ".", "NetworkTxBytes", ".", ".", ".", "." ]
          ],
          stat = "Sum",
          period = 60
        }
      },
      {
        type = "metric",
        x    = 0,
        y    = 12,
        width = 24,
        height = 6,
        properties = {
          title = "ALB Target Response Time",
          view = "timeSeries",
          region = "us-east-2",
          metrics = [
            [ "AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.strapi_alb.arn_suffix, "TargetGroup", aws_lb_target_group.strapi_tg.arn_suffix ]
          ],
          period = 60,
          stat   = "Average"
        }
      }
    ]
  })
}

