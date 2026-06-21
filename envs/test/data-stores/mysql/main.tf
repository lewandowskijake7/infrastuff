provider "aws" {
  region = "us-east-2"
}

resource "aws_db_instance" "test_db" {
  identifier_prefix = "jlew"
  engine = "mysql"
  allocated_storage = 10
  instance_class = "db.t3.micro"
  skip_final_snapshot = true
  db_name = "test_db"
  username = "admin"
  password = "password"
}

terraform {
    backend "s3" {
        key = "test/data-stores/mysql/terraform.tfstate"
    }
}