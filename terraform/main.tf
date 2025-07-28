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
  subnet_id = data.aws_subnets.default.ids[0]
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

