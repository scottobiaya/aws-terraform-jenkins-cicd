resource "aws_iam_role" "jenkins_role" {
  name = "jenkins_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "Pro-Jenkins"
  }
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkin_profile"

  role = aws_iam_role.jenkins_role.name
}