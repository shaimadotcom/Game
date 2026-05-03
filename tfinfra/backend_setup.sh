#!/bin/bash
# 1. System Updates and Docker Installation
apt-get update -y
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
systemctl enable docker

# Wait for Docker daemon to settle
sleep 10

# 2. Setup Application Directory
mkdir -p /app/data
cd /app

# 3. Download Backend Files
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/backend/package.json -o package.json || { echo "Failed to download package.json"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/backend/server.js -o server.js || { echo "Failed to download server.js"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/backend/Dockerfile -o Dockerfile || { echo "Failed to download Dockerfile"; exit 1; }

# Initialize the data file on the host
echo '[]' > /app/data/scores.json

# 5. Build and Run with Data Persistence
docker build -t backend .
# We mount the /app/data folder so scores aren't deleted if the container stops
docker run -d -p 3000:3000 -v /app/data:/app/data --name backend backend