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

# 3. Create Backend Files
cat << 'PKGJSON' > package.json
{
  "name": "game-leaderboard-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
PKGJSON

cat << 'SERVERJS' > server.js
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_FILE = path.join(__dirname, 'data', 'scores.json');

app.use(cors());
app.use(express.json());

// Ensure data directory exists
const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

if (!fs.existsSync(DATA_FILE)) {
  fs.writeFileSync(DATA_FILE, JSON.stringify([]));
}

function readScores() {
  try {
    const data = fs.readFileSync(DATA_FILE, 'utf8');
    return JSON.parse(data);
  } catch (err) {
    return [];
  }
}

function writeScores(scores) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(scores, null, 2));
    return true;
  } catch (err) {
    return false;
  }
}

app.get('/api/leaderboard', (req, res) => {
  const scores = readScores();
  scores.sort((a, b) => b.score - a.score);
  res.json({ success: true, leaderboard: scores.slice(0, 10) });
});

app.post('/api/scores', (req, res) => {
  const { name, score } = req.body;
  const scores = readScores();
  const newScore = {
    id: Date.now() + Math.random().toString(36).substr(2, 9),
    name: name.trim().substring(0, 50),
    score: score,
    timestamp: new Date().toISOString()
  };
  scores.push(newScore);
  writeScores(scores);
  res.status(201).json({ success: true, score: newScore });
});

app.listen(PORT, () => console.log('Backend running on port ' + PORT));
SERVERJS

# Initialize the data file on the host
echo '[]' > /app/data/scores.json

# 4. Create Dockerfile
cat << 'DOCKERFILE' > Dockerfile
FROM node:18
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
DOCKERFILE

# 5. Build and Run with Data Persistence
docker build -t backend .
# We mount the /app/data folder so scores aren't deleted if the container stops
docker run -d -p 3000:3000 -v /app/data:/app/data --name backend backend