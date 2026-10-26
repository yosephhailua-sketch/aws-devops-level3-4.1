#!/bin/bash
###########################################################
# Perform basic configuration management
###########################################################
# - upgrade os & install ansible
dnf -y upgrade
dnf -y install ansible rsync

cat<<"EOA" > config-and-deploy.web.yml
# Inputs - need to know:
# * nginx package name: "nginx" on Amazon Linux 2023
# * git package name: "git-core"
# * web folder location: "/usr/share/nginx/html"
# * application code git URL: "https://github.com/nenemustafa/Hellome.git"
# * application source file: "heyme" in the repository root


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
