###########################################################
# Terraform iterration 2: terraform + user-data(config mgmt)
###########################################################

cd ~/aws-devops-level3

# - create user data script
cat<<"EOF" > user-data.web.sh
#!/bin/bash
###########################################################
# Perform configuration management
###########################################################
# Inputs - need to know:
# * nginx package name : "nginx1" from amazon-linux-extras
# * git package name: "git-core"

# - become root
# sudo bash

# - upgrade os
yum -y update && yum -y upgrade

# - install nginx
yum install nginx -y

# - start nginx
service nginx start

# - install git tool
yum -y install git-core

# - return to normal user mode
# exit
EOF

# - change main.tf to include user-data
cat <<"EOF" > main.tf
resource "aws_instance" "devops-school-level3" {
  ami             = var.ami_id
  instance_type   = var.ec2_type
  subnet_id       = var.subnet_id
  key_name        = var.keypair

  vpc_security_group_ids = [var.main_sg_id]

  user_data = file("user-data.web.sh")
  user_data_replace_on_change = true

  tags = {
    Name = var.ec2_name
  }
}
EOF

# - quick try command to see that our syntax is correct

terraform plan -out=tfplan

terraform apply "tfplan"
# ec2_public_dns_name = "ec2-13-48-135-138.eu-north-1.compute.amazonaws.com""

MY_EC2=$(terraform output -json | jq -r .ec2_public_dns_name.value)

# - wait four cloud-init process user-data script (press Ctrl+C to abort)
ssh -i $MY_SSH ec2-user@$MY_EC2 tail -f /var/log/cloud-init-output.log

###########################################################
# Manual deploy of the code from Git repo
###########################################################
# - login into ec2 - deployment preperation
ssh -i $MY_SSH ec2-user@$MY_EC2

# - clone application code
rm -rf hello-web
git clone https://github.com/nenemustafa/Hellome.git

# - cleanup previous application code
sudo rm -f /usr/share/nginx/html/*.html

# - install applicaton code
sudo cp hellome/html/* /usr/share/nginx/html/

# - return to your machine
exit

###########################################################
# Verify the deploy
###########################################################
# Inputs - need to know:
# * DNS name of the web server: $MY_EC2

# - automate: (open your web browser and surf to) => use curl
# ouput of echo $? means:
#  O = YES, success
#  1 = Computer says NO
curl http://$MY_EC2/ 2>&1 | grep 'Hey Me!' > /dev/null && echo YES
echo $?
