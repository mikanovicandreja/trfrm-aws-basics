terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
    region = "us-west-1"
}

# ------------ AZs ------------ #
data "aws_availability_zones" "available" {
  #Loading all available AZs in the region
}

# -------- Resources --------- #
# -------- VPC --------- #
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
      Name = "custom-vpc"
  }
}

# -------- Internet Gateway --------- #
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# -------- Subnets --------- #
resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
      Name = "public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
      Name = "public-subnet-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags = {
      Name = "private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
  tags = {
      Name = "private-subnet-b"
  }
}

# -------- Route Table --------- #
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-rt"
  }
}

# -------- Route Table Association --------- #
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# -------- Security Group --------- #
# -------- SSH + HTTP/HTTPS Access --------- #
resource "aws_security_group" "ec2_web_ssh" {
  vpc_id      = aws_vpc.main.id
  name        = "allow_web&ssh"
  description = "Allow HTTP/HTTPS traffic & SSH access"
  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["45.87.212.180/32"] # Allow access ONLY from my IP (static IP from SurfShark VPN)
  }
  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Equivalent to all ports
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    name = "ec2-ssh+web"
  }
}

resource "aws_security_group" "rds_sg" {
  name = "rds-sg"
  description = "Allow PostgreSQL access from EC2"
  vpc_id = aws_vpc.main.id
  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_web_ssh.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -------- Key Deployer --------- #
resource "aws_key_pair" "deployer" {
  key_name   = "new_key"
  public_key = file("/home/andreja/.ssh/new_key.pub")
}

# ------------ AMI for Amazon Linux 2 ----------- #
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners = ["137112412989"]

  filter {
    name = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
}

# -------- EC2 instance --------- #
resource "aws_instance" "my_ec2" {
  ami = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.deployer.key_name
  subnet_id = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_web_ssh.id]
  associate_public_ip_address = true
  user_data = <<EOF
#!/bin/bash
sudo yum update -y

# --- Install Apache --- #
sudo yum install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd

# --- Install PostgreSQL 14 --- #
sudo amazon-linux-extras install postgresql14
sudo yum clean metadata
sudo yum install -y postgresql

# --- Give permissions to ec2-user --- #
sudo usermod -a -G apache ec2-user

# --- Install SSL certificate for HTTPS --- #
sudo yum install -y mod_ssl
sudo openssl genrsa -out custom.key 4096

sudo systemctl restart httpd
EOF
  tags = {
        Name = "test-ec2"
        Description = "Test instance"
        CostCenter = "123456"
  }
}

# ------------ RDS Subnet Group ----------- #
resource "aws_db_subnet_group" "rds_sn_group" {
  name = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags = {
    Name = "rds-subnet-group"
  }
}

# -------- RDS: PostgreSQL ------- #
resource "aws_db_instance" "rds_psql" {
  identifier = "postgres-db"
  engine = "postgres"
  engine_version = "14"
  instance_class = "db.t3.micro"
  allocated_storage = 8
  db_name = "mydb"
  username = "postgres"
  password = "Andreja2425"
  publicly_accessible = false
  multi_az = true
  db_subnet_group_name = aws_db_subnet_group.rds_sn_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true
  tags = {
    Name = "PostgreSQL-RDS"
  }
}