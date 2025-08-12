variable "student_name" {
  description = "Your full name in lowercase without spaces"
  type        = string
}

variable "student_number" {
  description = "Your student number (used to derive last 4 digits)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "List of availability zones to use (must be at least 2)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_bits" {
  description = "Bits to add to VPC mask to create public subnets (e.g. 8 -> /24)"
  type        = number
  default     = 8
}

variable "private_subnet_bits" {
  description = "Bits to add to VPC mask to create private subnets (e.g. 8 -> /24)"
  type        = number
  default     = 8
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket for static files (must be globally unique)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet egress"
  type        = bool
  default     = true
}
