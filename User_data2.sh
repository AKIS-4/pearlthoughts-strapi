#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y docker.io 
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker
sudo docker run -d -p 5432:5432 --name postgres \
 -e POSTGRES_PASSWORD=${DATABASE_PASSWORD} \
 -e POSTGRES_USER=${DATABASE_USERNAME} \
 -e POSTGRES_DB=${DATABASE_NAME} \
 -v pgdata:/var/lib/postgresql/data \
 --restart unless-stopped \
 postgres:15-alpine