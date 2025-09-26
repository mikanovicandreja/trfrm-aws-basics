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

# --- RDS Failover Check --- #
aws rds reboot-db-instance --db-instance-identifier <INSTANCE_NAME> --force-failover
while true; do host postgres-db.crk4kickasi7.us-west-1.rds.amazonaws.com ; sleep 3; done
