# AWS Terraform Jenkins CI/CD

## Project Overview

This project demonstrates an automated Infrastructure as Code (IaC) and CI/CD workflow using **Terraform, AWS, Jenkins, Docker, Nginx, GitHub, and Amazon S3**.

Terraform is used to provision the AWS infrastructure, while Jenkins automatically executes the Terraform workflow whenever changes are pushed to GitHub.

The application infrastructure consists of two Nginx application instances managed through an **Auto Scaling Group (ASG)** and placed behind an **Application Load Balancer (ALB)**.

A separate Jenkins EC2 instance is used to run the CI/CD pipeline and Terraform commands.

Terraform state is stored remotely in **Amazon S3**, allowing both the local Terraform environment and Jenkins to use the same state.

---

## Architecture

```text
                         ┌──────────────────┐
                         │      GitHub      │
                         │  Terraform Code  │
                         │    Jenkinsfile   │
                         └────────┬─────────┘
                                  │
                                  │ Git Push
                                  ▼
                         ┌──────────────────┐
                         │      Jenkins     │
                         │      EC2         │
                         │                  │
                         │ Terraform        │
                         │ AWS CLI          │
                         │ Docker           │
                         └────────┬─────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
                    ▼                           ▼
          ┌──────────────────┐       ┌──────────────────┐
          │   Amazon S3      │       │       AWS        │
          │                  │       │  Infrastructure  │
          │ Terraform State  │       │                  │
          │ Remote Backend   │       │ VPC / ALB / ASG  │
          └──────────────────┘       └────────┬─────────┘
                                               │
                                  ┌────────────┴────────────┐
                                  │                         │
                                  ▼                         ▼
                         ┌────────────────┐        ┌────────────────┐
                         │ Application    │        │ Application    │
                         │ EC2 Instance   │        │ EC2 Instance   │
                         │                │        │                │
                         │ Docker         │        │ Docker         │
                         │ Nginx :80     │        │ Nginx :80     │
                         └────────────────┘        └────────────────┘
                                  ▲                         ▲
                                  │                         │
                                  └───────────┬─────────────┘
                                              │
                                      ┌───────┴───────┐
                                      │      ALB      │
                                      │               │
                                      │ HTTP :80      │
                                      │ Jenkins :8080 │
                                      └───────┬───────┘
                                              │
                                              ▼
                                      Internet Traffic
```

---

## Technologies Used

* **AWS**
* **Terraform**
* **Jenkins**
* **GitHub**
* **Docker**
* **Nginx**
* **Amazon S3**
* **Amazon EC2**
* **Application Load Balancer**
* **Auto Scaling Group**
* **IAM**
* **Amazon SSM**
* **Ubuntu Linux**

---

## AWS Infrastructure

Terraform provisions the following AWS resources:

### Networking

* VPC
* Two public subnets
* Internet Gateway
* Route tables
* Route table associations

The subnets are distributed across two Availability Zones:

* `us-east-1a`
* `us-east-1b`

Public IP addressing is enabled for the EC2 instances.

---

## Application Load Balancer

An Application Load Balancer distributes traffic to the application instances.

### Application listener

```text
HTTP :80
```

Traffic is forwarded to the Nginx target group.

### Jenkins listener

```text
HTTP :8080
```

Traffic is forwarded to the Jenkins target group.

---

## Application Tier

The application tier uses an Auto Scaling Group.

The configuration maintains:

```text
Desired capacity: 2
Minimum capacity: 1
Maximum capacity: 2
```

The EC2 instances are created from a Terraform Launch Template.

Each application instance:

1. Starts from an Ubuntu AMI.
2. Updates the Ubuntu package repositories.
3. Installs Docker.
4. Starts the Docker service.
5. Installs the Amazon SSM Agent.
6. Pulls the Nginx Docker image.
7. Runs Nginx as a Docker container.
8. Exposes Nginx on port 80.

The container is configured with:

```text
--restart unless-stopped
```

so Docker automatically restarts the Nginx container if necessary.

---

## Jenkins Server

Jenkins runs on a dedicated EC2 instance.

The Jenkins Launch Template installs:

* Jenkins
* Java 21
* Docker
* AWS CLI
* Terraform
* unzip
* wget
* fontconfig
* Amazon SSM Agent

The Jenkins user is also added to the Docker group so Jenkins can execute Docker commands.

Terraform is installed automatically during EC2 initialization.

---

## Jenkins and Terraform IAM

The Jenkins EC2 instance assumes the IAM role:

```text
jenkins_role
```

The role allows the Jenkins server to interact with AWS.

Amazon SSM is also enabled so the instance can be managed through AWS Systems Manager without requiring direct administrative access to the server.

For the development version of this project, the Jenkins role has broad AWS permissions to allow Terraform to provision the infrastructure.

For production environments, these permissions should be replaced with a least-privilege IAM policy containing only the actions required by Terraform.

---

## Application IAM

The application EC2 instances use:

```text
ec2_role
```

and the associated instance profile:

```text
test_profile
```

The role includes:

```text
AmazonSSMManagedInstanceCore
```

which allows the instances to be managed using AWS Systems Manager.

---

## Terraform Remote State

Terraform state is stored remotely in Amazon S3.

The backend configuration uses:

```text
Bucket:
scott-terraform-state-585768150796

Key:
terraform/terraform.tfstate

Region:
us-east-1
```

The S3 bucket has versioning enabled.

This provides a single shared Terraform state for both:

* Local Terraform
* Jenkins Terraform

This is important because Jenkins and the local development machine must not maintain separate Terraform states for the same infrastructure.

### Backend configuration

```hcl
terraform {
  backend "s3" {
    bucket = "scott-terraform-state-585768150796"
    key    = "terraform/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

## Why Remote State Is Used

Originally, Terraform used local state files.

This caused a problem because the local computer and Jenkins had different Terraform states.

The local environment knew that resources such as the ALB, target groups, and IAM roles already existed.

Jenkins, however, had a different local state and attempted to create the same resources again.

AWS returned errors such as:

```text
Resource already exists
```

Moving the Terraform state to Amazon S3 solved this problem.

Both environments now use the same Terraform state.

---

## Jenkins Pipeline

The Jenkins pipeline follows this workflow:

```text
GitHub
   │
   ▼
Jenkins Checkout
   │
   ▼
Terraform Init
   │
   ▼
Terraform Format Check
   │
   ▼
Terraform Validate
   │
   ▼
Terraform Plan
   │
   ▼
Terraform Apply
   │
   ▼
AWS Infrastructure
```

The pipeline retrieves the latest Terraform configuration from GitHub and executes Terraform automatically.

---

## Terraform Pipeline Stages

### 1. Checkout

Jenkins retrieves the latest code from GitHub.

### 2. Terraform Init

Terraform initializes the AWS provider and connects to the S3 remote backend.

```bash
terraform init
```

### 3. Terraform Format Check

The Terraform configuration is checked for formatting issues.

```bash
terraform fmt -check
```

### 4. Terraform Validate

Terraform validates the configuration.

```bash
terraform validate
```

### 5. Terraform Plan

Terraform calculates the changes required to bring the AWS environment in line with the configuration.

```bash
terraform plan -out=tfplan
```

### 6. Terraform Apply

The saved Terraform plan is applied automatically.

```bash
terraform apply -auto-approve tfplan
```

---

## Automated Deployment

The intended workflow is:

```text
Developer
    │
    │ git push
    ▼
GitHub
    │
    │ webhook / Jenkins trigger
    ▼
Jenkins
    │
    ├── Checkout
    ├── Terraform Init
    ├── Terraform Format
    ├── Terraform Validate
    ├── Terraform Plan
    └── Terraform Apply
              │
              ▼
             AWS
```

This allows infrastructure changes committed to GitHub to be automatically deployed through Jenkins.

---

## Docker Deployment

Docker is installed automatically on the application EC2 instances.

The application container is based on the official Nginx image.

The container is started using:

```bash
docker run -d \
  --name nginx \
  --restart unless-stopped \
  -p 80:80 \
  nginx
```

The application is therefore accessible through port 80.

---

## Security Groups

### Load Balancer Security Group

The ALB allows inbound:

```text
TCP 80
TCP 8080
```

from the internet.

### Application Security Group

The application instances allow:

```text
TCP 80
```

from the ALB security group.

SSH is also currently permitted for administration.

### Jenkins Security Group

The Jenkins server allows:

```text
TCP 8080
```

from the ALB security group.

SSH is currently permitted for administration.

For production, SSH access should be restricted or replaced with Systems Manager Session Manager.

---

## Health Checks

The application target group performs HTTP health checks against:

```text
/
```

on port:

```text
80
```

The Jenkins target group performs HTTP health checks against:

```text
/
```

on port:

```text
8080
```

This allows the Application Load Balancer to determine whether the targets are available.

---

## Memory and Swap

The Jenkins EC2 instance uses a small instance size, so a swap file can be configured to reduce memory pressure during Terraform and Jenkins operations.

A 2 GB swap file can be created with:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

To make it persistent across reboots:

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

The configuration can be verified using:

```bash
free -h
```

and:

```bash
swapon --show
```

---

## Project Structure

```text
AWS-Terraform-Jenkins-CI-CD/
│
├── main.tf
├── provider.tf
├── variables.tf
├── backend.tf
├── Jenkinsfile
├── .gitignore
├── .terraform.lock.hcl
│
└── docs/
    ├── architecture.png
    └── deployment-flow.png
```

Terraform state files are intentionally excluded from Git.

```text
terraform.tfstate
terraform.tfstate.backup
```

The state is stored remotely in Amazon S3.

---

## Prerequisites

Before deploying the project, the following are required:

* AWS account
* AWS CLI
* Terraform
* Git
* GitHub repository
* Jenkins
* Docker knowledge
* AWS IAM permissions
* SSH key pair

AWS CLI should be configured with credentials capable of provisioning the required AWS resources.

---

## Deploying Locally

Clone the repository:

```bash
git clone https://github.com/scottobiaya/aws-terraform-jenkins-cicd.git
```

Change into the project directory:

```bash
cd aws-terraform-jenkins-cicd
```

Initialize Terraform:

```bash
terraform init
```

Format the configuration:

```bash
terraform fmt
```

Validate the configuration:

```bash
terraform validate
```

Review the infrastructure changes:

```bash
terraform plan
```

Apply the configuration:

```bash
terraform apply
```

---

## Deploying Through Jenkins

Jenkins should be configured to use the GitHub repository:

```text
aws-terraform-jenkins-cicd
```

The Jenkins pipeline retrieves the repository and executes the Terraform workflow.

The pipeline should use:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan
```

Because Terraform state is stored in S3, Jenkins uses the same infrastructure state as the local Terraform environment.

---

## Verification

After deployment, verify the infrastructure in AWS.

### Check the application

Open the Application Load Balancer DNS name in a browser:

```text
http://<ALB-DNS-NAME>
```

The Nginx welcome page should be displayed.

### Check Jenkins

Open:

```text
http://<ALB-DNS-NAME>:8080
```

The Jenkins interface should be available.

### Check Terraform

Run:

```bash
terraform plan
```

A successful deployment should return:

```text
No changes. Your infrastructure matches the configuration.
```

---

## Key Lessons From the Project

This project demonstrates several important DevOps and cloud engineering concepts:

* Infrastructure as Code using Terraform
* AWS networking
* VPC and subnet design
* Application Load Balancing
* Auto Scaling Groups
* EC2 Launch Templates
* Docker container deployment
* Jenkins CI/CD
* GitHub source control
* Terraform remote state
* S3 state management
* IAM roles and instance profiles
* AWS Systems Manager
* Infrastructure validation and planning
* Automated infrastructure deployment
* Troubleshooting AWS health checks
* Linux memory and swap management

---

## Future Improvements

Possible improvements include:

* Replace `AdministratorAccess` on the Jenkins role with least-privilege IAM permissions.
* Restrict SSH access.
* Use AWS Systems Manager instead of direct SSH access.
* Store sensitive values in AWS Secrets Manager or Parameter Store.
* Add automated application tests.
* Add Terraform security scanning.
* Add Terraform linting.
* Add separate development, staging, and production environments.
* Use a dedicated Terraform state bucket managed separately from the application infrastructure.
* Add CloudWatch monitoring and logging.
* Use HTTPS with an ACM certificate.
* Use a custom Docker image instead of pulling the default Nginx image.
* Add blue/green or rolling deployment strategies.

---

## Conclusion

This project demonstrates an end-to-end Infrastructure as Code and CI/CD workflow.

GitHub provides version control, Jenkins automates the deployment process, Terraform provisions and manages AWS infrastructure, S3 provides centralized Terraform state, Docker runs the Nginx application, and the AWS Application Load Balancer distributes traffic across the application instances.

The resulting workflow provides a foundation for implementing repeatable and automated cloud infrastructure deployments using modern DevOps practices.
