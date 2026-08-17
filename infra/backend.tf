terraform {
  backend "s3" {
    bucket = "bsoyka-tfstate"
    key    = "brand.tfstate"
    region = "us-east-1"
  }
}
