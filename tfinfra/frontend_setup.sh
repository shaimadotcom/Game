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
mkdir -p /app
cd /app

# 3. Download Frontend Files
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/index.html -o index.html || { echo "Failed to download index.html"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/style.css -o style.css || { echo "Failed to download style.css"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/script.js -o script.js || { echo "Failed to download script.js"; exit 1; }

# Download sound files
mkdir -p sound
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/sound/blockchain.png -o sound/blockchain.png
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/sound/Stone_hit5.ogg -o sound/Stone_hit5.ogg
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/sound/Stone_hit6.ogg -o sound/Stone_hit6.ogg
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/sound/Stone_mining4.ogg.mp3 -o sound/Stone_mining4.ogg.mp3
curl -fsSL https://raw.githubusercontent.com/shaimadotcom/Game/main/frontend/sound/subwoofer_lullaby.mp3 -o sound/subwoofer_lullaby.mp3

# 4. Create Dockerfile using the "COPY ALL" method
cat <<-NGINXDF > Dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html/
EXPOSE 80
NGINXDF

# 5. Build and Run Container
docker build -t frontend .
docker run -d -p 80:80 --name frontend frontend