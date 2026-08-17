###########################################################
# Terraform iteration 4: terraform + user-data + deploy(ansible)
###########################################################

MY_SSH="$HOME/.ssh/petter-ec2-key.pem"
cd "$(dirname "$0")/.."

# - create user data script

cat<<"EOF" > user-data.web.sh
#!/bin/bash
###########################################################
# Perform basic configuration management
###########################################################
# - upgrade os & install ansible
dnf -y upgrade
dnf -y install ansible rsync

cat<<"EOA" > config-and-deploy.web.yml
# Inputs - need to know:
# * nginx package name : "nginx1" from amazon-linux-extras
# * git package name: "git-core"
# * web folder location: "/usr/share/nginx/html"
# * application code git URL: "https://github.com/nenemustafa/Hellome.git"
# * need to know: application folder structure for html: "Hey-Me/html/"


- hosts: localhost
  become: true

  tasks:

  ### Application configuration management
  - name: install nginx & git tool
    yum:
      name: "{{ packages }}"
      state: latest
      update_cache: yes
      lock_timeout: 180
    vars:
      packages:
      - nginx
      - git-core

  - name: start nginx
    service:
      name: nginx
      state: started
      enabled: yes

  ### Application deployment
  - name: clone application code
    git:
      repo: 'https://github.com/nenemustafa/Hellome.git'
      dest: /tmp/hello-me
      clone: yes
      update: yes

  - name: install application code
    synchronize:
      src: /tmp/hello-me/heyme
      dest: /usr/share/nginx/html/index.html
EOA

ansible-playbook -v config-and-deploy.web.yml
EOF

# - re-build using new user-data instructions
terraform plan -out=tfplan

# The script stops after creating the reviewable Terraform plan.
# Review manually with: terraform show -no-color tfplan
# Apply manually only after review: terraform apply "tfplan"
# Terraform destroy is intentionally excluded from this script.
