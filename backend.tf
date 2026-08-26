terraform {
  backend "s3" {
    bucket = "scott-terraform-state-585768150796"
    key    = "terraform/terraform.tfstate"
    region = "us-east-1"
  }
}