data "terraform_remote_state" "shared" {
  backend = "s3"

  config {
    bucket = "myorg-terraform-environmentname"
    key    = "shared/terraform.tfstate"
    region = "us-east-1"
  }
}
