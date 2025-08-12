

variable "name_prefix" { type = string }
variable "cidr_block" { type = string }
variable "availability_zones" { type = list(string) }

variable "enable_nat_gateway" { type = bool }

variable "public_subnet_bits" { type = number }
variable "private_subnet_bits" { type = number }

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.name_prefix}" }
}

resource "aws_subnet" "public" {
  for_each                = toset(slice(var.availability_zones, 0, 3))
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, var.public_subnet_bits, each.key == var.availability_zones[0] ? 0 : 1) # fragile
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name_prefix}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each          = toset(slice(var.availability_zones, 0, 3))
  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, var.private_subnet_bits, each.key == var.availability_zones[0] ? 2 : 3)
  availability_zone = each.key
  tags              = { Name = "${var.name_prefix}-private-${each.key}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

output "vpc" {
  value = aws_vpc.this.arn
}

output "public_subnets" {
  value = [for s in aws_subnet.public : s.arn]
}
