provider "aws" {
    region = "eu-north-1"
}


# Amazon Machine Image(AMI) for the instance
resource "aws_instance" "example" {
    ami           = "ami-006b4a3ad5f56fbd6"
    instance_type = "t3.micro"

    tags = {
        Name = "ExampleInstance"
    }
}