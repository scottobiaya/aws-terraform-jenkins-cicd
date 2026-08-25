resource "aws_vpc" "main" {
  cidr_block       = var.vpc-cidr_block
  instance_tenancy = "default"

  tags = {
    Name = "Pro"
  }
}

resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Pro"
  }
}

resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Pro"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Pro"
  }
}


resource "aws_route_table" "sub1-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Pro"
  }
}


resource "aws_route_table" "sub2-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Pro"
  }
}

resource "aws_route_table_association" "sub1-rt-ass" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.sub1-rt.id
}

resource "aws_route_table_association" "sub2-rt-ass" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.sub2-rt.id
}


resource "aws_lb" "test" {
  name               = "Pro-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.LB-sg.id]
  subnets = [aws_subnet.sub1.id,
  aws_subnet.sub2.id]


  tags = {
    Environment = "Pro"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "Pro-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "traffic-port"

  }

}

resource "aws_lb_target_group" "jenkins-tg" {
  name     = "Pro-jenkins-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    protocol = "HTTP"
    path     = "/"
    port     = "traffic-port"
    matcher  = "200-403"
  }

}



resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "80"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


resource "aws_lb_listener" "jenkins_end" {
  load_balancer_arn = aws_lb.test.arn
  port              = "8080"
  protocol          = "HTTP"


  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins-tg.arn
  }
}




resource "aws_launch_template" "Pro-ec2" {
  name_prefix   = "Pro"
  image_id      = "ami-0b6d9d3d33ba97d99"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true

    security_groups = [
      aws_security_group.ASG.id
    ]
  }

  user_data = base64encode(<<-EOF
  #!/bin/bash
  set -e

  sed -i 's|http://us-east-1.ec2.archive.ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

  apt update -y
  apt install -y docker.io snapd

  systemctl enable --now docker

  snap install amazon-ssm-agent --classic
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

  docker pull nginx

  docker rm -f nginx 2>/dev/null || true

  docker run -d \
    --name nginx \
    --restart unless-stopped \
    -p 80:80 \
    nginx
EOF
  )

  key_name = var.key-pair

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2-profile.name
  }
}

resource "aws_autoscaling_group" "bar" {
  desired_capacity = 2
  max_size         = 2
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.sub1.id,
    aws_subnet.sub2.id
  ]

  target_group_arns = [
    aws_lb_target_group.tg.arn
  ]

  launch_template {
    id      = aws_launch_template.Pro-ec2.id
    version = "$Latest"
  }

  tag {
    key                 = "Role"
    value               = "app"
    propagate_at_launch = true
  }
}





resource "aws_iam_role" "ec2-role" {
  name = "ec2_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    tag-key = "Pro"
  }
}

resource "aws_iam_role_policy" "ec2-policy" {
  name = "test_policy"
  role = aws_iam_role.ec2-role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:Describe*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2-profile" {
  name = "test_profile"
  role = aws_iam_role.ec2-role.name
}

resource "aws_security_group" "LB-sg" {
  name        = "lb-sg"
  description = "Allow internet inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {
    Name = "Pro-sg"
  }
}


resource "aws_security_group" "ASG" {
  name        = "ec2-sg"
  description = "Allow lb inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.LB-sg.id]

  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {
    Name = "Pro-sg"
  }
}


resource "aws_security_group" "jenkins-sg" {
  name        = "jenkins-sg"
  description = "Allow vpc inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.LB-sg.id]

  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }

  tags = {
    Name = "Pro-jenkins-sg"
  }
}


resource "aws_launch_template" "Pro-jenkins" {
  name_prefix   = "Pro-jenkins-"
  image_id      = "ami-0b6d9d3d33ba97d99"
  instance_type = "t2.micro"

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = true

    security_groups = [
      aws_security_group.jenkins-sg.id
    ]
  }
  user_data = base64encode(<<-EOF
  #!/bin/bash
  set -e

  echo "===== Starting Jenkins installation ====="

  sed -i 's|http://us-east-1.ec2.archive.ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

  echo "Updating packages..."
  apt update -y

  echo "Installing required packages..."
  apt install -y \
    wget \
    awscli \
    fontconfig \
    openjdk-21-jre \
    docker.io \
    unzip \
    snapd

  echo "Starting Docker..."
  systemctl enable --now docker

  echo "Installing and starting Amazon SSM Agent..."
  snap install amazon-ssm-agent --classic
  systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

  echo "Adding Jenkins repository key..."
  mkdir -p /etc/apt/keyrings

  wget -O /etc/apt/keyrings/jenkins-keyring.asc \
    https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

  echo "Adding Jenkins repository..."
  echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    > /etc/apt/sources.list.d/jenkins.list

  echo "Updating package lists..."
  apt update -y

  echo "Installing Jenkins..."
  apt install -y jenkins

  echo "Installing Terraform..."

  TERRAFORM_VERSION="1.15.9"

  wget -q \
    "https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip" \
    -O /tmp/terraform.zip

  unzip -o /tmp/terraform.zip -d /usr/local/bin/

  chmod +x /usr/local/bin/terraform

  rm -f /tmp/terraform.zip

  echo "Adding Jenkins user to Docker group..."
  usermod -aG docker jenkins

  echo "Enabling Jenkins..."
  systemctl enable jenkins

  echo "Starting Jenkins..."
  systemctl start jenkins

  echo "Checking installations..."
  echo "===== Terraform ====="
  terraform version

  echo "===== AWS CLI ====="
  aws --version

  echo "===== Docker ====="
  docker --version

  echo "===== Java ====="
  java -version

  echo "===== Jenkins ====="
  systemctl status jenkins --no-pager || true

  echo "===== SSM Agent ====="
  systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service --no-pager || true

  echo "===== Jenkins installation completed ====="
EOF
  )

  key_name = var.key-pair

  iam_instance_profile {
    name = data.aws_iam_instance_profile.jenkins_profile.name
  }
}


data "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkin_profile"
}

resource "aws_autoscaling_group" "jenkins" {
  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.sub1.id
  ]

  target_group_arns = [
    aws_lb_target_group.jenkins-tg.arn
  ]

  launch_template {
    id      = aws_launch_template.Pro-jenkins.id
    version = "$Latest"
  }
}
