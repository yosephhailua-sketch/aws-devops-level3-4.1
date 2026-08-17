###########################################################
# Terraform iterration 3: terraform + user-data + deploy(bash)
###########################################################

MY_SSH="$HOME/.ssh/id_rsa_level3"
PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

# - create user data script
cat<<"EOF" > user-data.web.sh
#!/bin/bash
###########################################################
# Perform configuration management
###########################################################

# - become root
# sudo bash

# - upgrade os
yum -y update && yum -y upgrade

# - install nginx
yum install nginx -y

# - enable and start nginx automatically
systemctl enable --now nginx

# - install git tool
yum -y install git-core

# - return to normal user mode
# exit

###########################################################
# Manual deploy of the code from Git repo
###########################################################

# - clone application code
rm -rf Hellome
git clone https://github.com/nenemustafa/Hellome.git

# - cleanup previous application code
sudo rm -f /usr/share/nginx/html/*.html

# - install applicaton code
sudo cp Hellome/heyme /usr/share/nginx/html/index.html
EOF

# - re-build using new user-data instructions
terraform plan -out=tfplan
# Saved the plan to: tfplan

# To perform exactly these actions, run the following command to apply:
#     terraform apply "tfplan"
terraform apply "tfplan"
# ec2_public_dns_name = "ec2-52-211-182-254.eu-west-1.compute.amazonaws.com"
export MY_EC2=$(terraform output -json | jq -r .ec2_public_dns_name.value)
ssh -i $MY_SSH ec2-user@$MY_EC2 sudo tail -f /var/log/cloud-init-output.log

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
