#!/bin/bash
# Update system packages
yum update -y

# Install Git
yum install -y git

# Install unzip (required for Terraform)
yum install -y unzip

# Install AWS CLI v2
# Remove any old AWS CLI v2
sudo rm -rf /usr/local/aws-cli /usr/local/bin/aws

# Download AWS CLI v2.28.1
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.28.1.zip" -o "/tmp/awscliv2.zip"

# Unzip
unzip -o /tmp/awscliv2.zip -d /tmp

# Install
sudo /tmp/aws/install --update

# Ensure aws is in PATH (permanent for ec2-user)
echo 'export PATH=/usr/local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verify
aws --version
export PATH=$PATH:/usr/local/bin


# Verify AWS CLI installation
aws --version

# Install Terraform
TERRAFORM_VERSION="1.6.5"
curl -LO https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin/
chmod +x /usr/local/bin/terraform

# Verify Terraform installation
terraform version

# Clean up
rm -rf /tmp/awscliv2.zip /tmp/aws
rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip
