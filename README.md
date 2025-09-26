AWS Infrastructure Assignment
============================================================

Objective:
-----------
Deploy and configure an AWS environment that includes an EC2 instance,
a custom VPC with subnet, and an RDS PostgreSQL database. Secure and 
verify connectivity between components, and demonstrate failover. 

Requirements:
-------------
1. EC2 Instance
   - AMI: Amazon Linux 2 (64-bit)
   - Type: t2.micro
   - VPC: custom (non-default) -> create a new VPC
   - Subnet: custom public subnet (non-default) -> create a new subnet
   - Install PostgreSQL client
   - Install and start Apache Web Server
   - Enable:
       * Public access to Apache default web page
       * SSH access restricted only to your IP
   - Apply AWS tags:
       * Name = test-ec2
       * Description = Test instance
       * CostCenter = 123456

2. RDS Database
   - Engine: Amazon RDS for PostgreSQL
   - Instance type: db.t3.micro
   - Deployment: Multi-AZ
   - Configure connectivity between EC2 and RDS
   - Create one sample table with several columns and rows

3. Failover
   - Demonstrate RDS failover from primary instance to standby

4. Infrastructure as Code
   - Use Terraform or AWS CloudFormation to deploy all resources

Deliverables:
-------------
- Running infrastructure in AWS
- Verification of:
    * EC2 connectivity to RDS
    * Web server accessibility from the internet
    * Proper tagging on resources
- Presentation of RDS failover


# AWS VPC + EC2 + RDS Infrastructure (Terraform)

This Terraform configuration provisions a custom AWS infrastructure designed for running a simple **web application with a PostgreSQL backend**. It creates a secure, highly-available Virtual Private Cloud (VPC) environment, deploys an EC2 instance with Apache + PostgreSQL client tools, and sets up an RDS PostgreSQL instance in private subnets.

---

## 🏗️ What this code does

### 1. **VPC and Networking**

- **VPC**
  - Creates a new VPC (`10.0.0.0/16`) with DNS support and hostnames enabled.
  - Tagged as `custom-vpc`.

- **Internet Gateway (IGW)**
  - Provides internet access for public subnets.
  - Attached to the main VPC.

- **Subnets**
  - **Public Subnets**: Two (`10.0.1.0/24`, `10.0.2.0/24`) across separate Availability Zones. Instances in these subnets get public IPs.
  - **Private Subnets**: Two (`10.0.3.0/24`, `10.0.4.0/24`) also spread across AZs. Used for the RDS database.

- **Route Tables**
  - Public route table with a default route (`0.0.0.0/0`) pointing to the IGW.
  - Associated with both public subnets to enable outbound internet access.

---

### 2. **Security**

- **EC2 Security Group** (`allow_web&ssh`)
  - Allows inbound:
    - HTTP (80) from anywhere
    - HTTPS (443) from anywhere
    - SSH (22) only from a specific static IP (`45.87.212.180/32`)
  - Allows all outbound traffic.

- **RDS Security Group** (`rds-sg`)
  - Only allows PostgreSQL (5432) connections **from EC2 instances** in the `allow_web&ssh` security group.
  - Blocks all direct public access.

---

### 3. **Compute**

- **Key Pair**
  - Uses a local SSH public key (`/home/andreja/.ssh/new_key.pub`) for EC2 SSH access.

- **Amazon Machine Image (AMI)**
  - Automatically fetches the latest Amazon Linux 2 AMI in the chosen region.

- **EC2 Instance**
  - `t2.micro` instance launched in one of the public subnets.
  - Bootstrapped with **User Data script** that:
    - Updates the OS
    - Installs **Apache (httpd)** for serving web content
    - Installs **PostgreSQL client tools** for database connectivity
    - Adds `ec2-user` to Apache group for permissions
    - Installs `mod_ssl` and generates a self-signed key for HTTPS
  - Tagged with custom metadata (`Name`, `Description`, `CostCenter`).

---

### 4. **Database**

- **RDS Subnet Group**
  - Includes both private subnets for high availability.

- **RDS PostgreSQL Instance**
  - `db.t3.micro`, PostgreSQL 14 engine.
  - 8 GB storage, Multi-AZ enabled.
  - Not publicly accessible (only available from private subnets).
  - Credentials defined in Terraform (⚠️ should be moved to a secure secrets manager in production).
  - Tagged as `PostgreSQL-RDS`.

---

## 🔗 Resource Relationships

- **Public EC2 Instance** → Can receive traffic from the internet via the Internet Gateway and public route table.
- **EC2 Security Group** → Allows web traffic + restricted SSH.
- **EC2** → Connects to RDS using private networking (via RDS security group).
- **RDS** → Isolated in private subnets, accessible **only** from EC2 in the VPC.
- **Multi-AZ setup** ensures RDS is resilient across availability zones.

---

## 🌍 Region and Availability

- **Region**: `us-west-1`
- **AZs**: Terraform automatically fetches available AZs and distributes resources across them for high availability.

---

## ⚠️ Notes & Recommendations

- **Database password** is hardcoded in the Terraform file (`Andreja2425`). For production, use **AWS Secrets Manager** or Terraform variables with secure storage.
- **SSH access** is limited to one IP (good practice). Ensure you update it when your IP changes.
- **Self-signed SSL** is used on EC2; replace with a trusted certificate for real deployments.
- **Cost caution**: RDS with Multi-AZ enabled may incur ongoing costs even at the smallest instance size.

---

## ✅ Outcome

After applying this Terraform configuration, you get:
- A secure VPC with **public + private subnets**.
- A **public EC2 instance** running Apache (with HTTP/HTTPS enabled) and PostgreSQL client tools.
- A **private RDS PostgreSQL database**, isolated from the internet but reachable from EC2.
- Networking and security rules that enforce a clean **two-tier architecture**.

---

## 🖼️ Architecture Overview

### ASCII Diagram


                        +-------------------+
                        |   Internet        |
                        +-------------------+
                                 |
                           [ Internet Gateway ]
                                 |
               +-----------------+-----------------+
               |                                   |
      +-------------------+               +-------------------+
      | Public Subnet A   |               | Public Subnet B   |
      | (10.0.1.0/24)     |               | (10.0.2.0/24)     |
      +-------------------+               +-------------------+
               |                                   |
        +--------------+                    (optional capacity)
        |   EC2 Web    | 
        |  Apache +    |
        |  PostgreSQL  |
        |   Client     |
        +--------------+
               |
               | Security Group (allow web + ssh)
               |
     +------------------- VPC Peering -------------------+
               |
      +-------------------+               +-------------------+
      | Private Subnet A  |               | Private Subnet B  |
      | (10.0.3.0/24)     |               | (10.0.4.0/24)     |
      +-------------------+               +-------------------+
               |                                   |
            +-----------------------------------------+
            |           RDS PostgreSQL (Multi-AZ)     |
            |     Accessible only from EC2 SG         |
            +-----------------------------------------+

