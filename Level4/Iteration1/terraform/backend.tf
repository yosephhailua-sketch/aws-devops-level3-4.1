terraform {
  backend "s3" {
    bucket       = "apladmin-719857073076-terraform-state"
    key          = "level4/iteration1/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
