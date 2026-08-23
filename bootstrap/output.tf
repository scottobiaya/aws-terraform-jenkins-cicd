output "jenkins_role_name" {
  value = aws_iam_role.jenkins_role.name
}

output "jenkins_instance_profile_name" {
  value = aws_iam_instance_profile.jenkins_profile.name
}