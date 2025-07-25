#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y docker.io docker-compose
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker
sleep 20
cd /home/ubuntu/docks
docker-compose up -d
