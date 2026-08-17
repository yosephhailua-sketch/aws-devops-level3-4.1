###########################################################
# Github configuration
###########################################################
# - Add your public SSH key into your Github profile

###########################################################
# Level 4 Iteration 1: Clean slate setup
###########################################################
# - checkout main repo and create your personal branch
mkdir ~/aws-devops-level4-iteration1
cd ~/aws-devops-level4-iteration1
git clone git@github.com:Nation-devapl/aws-devops-level4-iteration1.git
cd aws-devops/src/level3
# (replace this with your real first name and last name)
git checkout -b <yourfirst>.<yourlastname>
git config --global push.autoSetupRemote true
git push

###########################################################
# Re-run terraform with some improvements
###########################################################

# - get back all important varaibles
MY_USER=$(aws sts get-caller-identity | jq -r .Arn | awk -F 'user/' '{print $2}')
MY_KEYNAME="devops.school.level3.${MY_USER}"
MY_SSH="$HOME/.ssh/id_rsa_level3"
MY_SG=$(aws ec2 describe-security-groups --group-names level3.${MY_USER} | jq -r '.SecurityGroups[].GroupId')
MY_SUBNET=$(aws ec2 describe-subnets --query "Subnets[*].{ID:SubnetId, AZ:AvailabilityZone, VPC:VpcId}" | jq -r '.[].ID' | head -1)
MY_AMI=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64 --query 'Parameters[].Value' --output text)

cat <<EOF > terraform.tfvars
ami_id = "${MY_AMI}"
subnet_id = "${MY_SUBNET}"
main_sg_id = "${MY_SG}"
ec2_type = "t3.micro"
ec2_name = "devops-school-level3.${MY_USER}"
keypair = "${MY_KEYNAME}"
EOF

# - do the init
terraform init

# - re-build using new user-data instructions
terraform apply -auto-approve
MY_EC2=$(terraform output -json | jq -r .ec2_public_dns_name.value)

# (wait a few seconds)
ssh -i $MY_SSH ec2-user@$MY_EC2 tail -f /var/log/cloud-init-output.log

# REVIEW: Historical SSH host details were removed before public release.
# ED25519 key fingerprint is SHA256:mnGronYOsCmY5NUPRhnV7pMyCfaZy96UNONnHQqd1/4.
# This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])? "yes"
# Warning: Permanently added 'ec2-13-51-55-55.eu-north-1.compute.amazonaws.com' (ED25519) to the list of known hosts.
# TASK [clone application code] **************************************************
# changed: [localhost] => {"after": "b9bb2320c61e01cad6e9070cfc92474c096c1bd5", "before": null, "changed": true}

# TASK [install applicaton code] *************************************************
# changed: [localhost] => {"changed": true, "cmd": "/usr/bin/rsync --delay-updates -F --compress --archive --out-format='<<CHANGED>>%i %n%L' /tmp/hello-web/html/ /usr/share/nginx/html/", "msg": ".d..t...... ./\n>f.st...... index.html\n", "rc": 0, "stdout_lines": [".d..t...... ./", ">f.st...... index.html"]}

# PLAY RECAP *********************************************************************
# localhost                  : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0

# Cloud-init v. 22.2.2 finished at Mon, 01 Sep 2025 17:09:44 +0000. Datasource DataSourceEc2.  Up 69.24 seconds

###########################################################
# Verify the deploy
###########################################################
# Inputs - need to know:
# * DNS name of the web server: $MY_EC2

# - automate: (open your web browser and surf to) => use curl
# ouput of echo $? means:
#  O = YES, success
#  1 = Computer says NO
curl http://$MY_EC2/ 2>&1 | grep 'Hello Me!' > /dev/null && echo YES
echo $?

###########################################################
# Destroy everything
###########################################################
terraform destroy
