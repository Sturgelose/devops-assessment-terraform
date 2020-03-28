// DISCLAIMER, I'm aware my terraform knowledge is not the best one, I've only played with terraform in the past!

provider "aws" {
  version = "~> 2.0"
  region  = "eu-north-1"
  profile = "travelperk"
}

terraform {
  required_version = "~> 0.12.0"
}

data "aws_iam_role" "task_ecs" {
  name = "ecsTaskExecutionRole"
}

data "aws_vpc" "default_vpc" {
  default = true
}


// SUBNETS
resource "aws_subnet" "subnetA" {
  cidr_block        = "172.31.32.0/20"
  vpc_id            = data.aws_vpc.default_vpc.id
  availability_zone = "eu-north-1a"
}

resource "aws_subnet" "subnetB" {
  cidr_block        = "172.31.0.0/20"
  vpc_id            = data.aws_vpc.default_vpc.id
  availability_zone = "eu-north-1b"
}

resource "aws_subnet" "subnetC" {
  cidr_block        = "172.31.16.0/20"
  vpc_id            = data.aws_vpc.default_vpc.id
  availability_zone = "eu-north-1c"
}



// LOAD BALANCER
resource "aws_lb" "loadBalancer" {
  // LoadBalancer to expose the API in port 80 (HTTP)
  name               = "flask-loadBalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loadbalancer.id]
  subnets            = [aws_subnet.subnetA.id, aws_subnet.subnetB.id, aws_subnet.subnetC.id]

  enable_deletion_protection = true
}

resource "aws_alb_target_group" "targetFlask" {
  name     = "targetFlask"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id
  target_type = "ip"
}
resource "aws_alb_listener" "listenerFlask" {
  load_balancer_arn = aws_lb.loadBalancer.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.targetFlask.id
    type             = "forward"
  }
}



// SECURITY GROUPS
resource "aws_security_group" "fargate" {
  // Security group to allow LB access fargate/ECS
  name        = "flask"
  description = "Allows TCP connection from LB to Fargate"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancer.id]
    self            = false
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "loadbalancer" {
  // Security group to allow internet access LB
  name        = "loadbalancer"
  description = "Allows HTTP incoming to LB"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// FARGATE/ECS
resource "aws_ecr_repository" "flaskRepository" {
  name = "eriber-flask"
}

resource "aws_ecs_cluster" "cluster" {
  name = "cluster"
}

resource "aws_ecs_task_definition" "flaskTask" {
  family                   = "flask-task"
  container_definitions    = file("./flask-task.json")
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = "arn:aws:iam::303981612052:role/ecsTaskExecutionRole"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
}

resource "aws_ecs_service" "flask-service" {
  name            = "flask-service"
  task_definition = aws_ecs_task_definition.flaskTask.id
  cluster         = aws_ecs_cluster.cluster.id

  desired_count = 2
  launch_type = "FARGATE"

  load_balancer {
    target_group_arn = aws_alb_target_group.targetFlask.id
    container_name = "flask-api"
    container_port = 5000
  }
  network_configuration {
    subnets         = [aws_subnet.subnetA.id, aws_subnet.subnetB.id, aws_subnet.subnetC.id]
    security_groups = [aws_security_group.fargate.id]
    assign_public_ip = true
  }
}
