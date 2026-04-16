#!/bin/bash
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

mkdir -p /app
cat <<-PKGJSON > /app/package.json
{
  "name": "game-leaderboard-backend",
  "version": "1.0.0",
  "description": "Leaderboard backend for tower block game",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
PKGJSON

cat <<-SERVERJS > /app/server.js
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_FILE = path.join(__dirname, 'data', 'scores.json');

app.use(cors());
app.use(express.json());

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
    console.error('Error reading scores:', err);
    return [];
  }
}

function writeScores(scores) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(scores, null, 2));
    return true;
  } catch (err) {
    console.error('Error writing scores:', err);
    return false;
  }
}

app.get('/api/leaderboard', (req, res) => {
  const scores = readScores();
  scores.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return new Date(b.timestamp) - new Date(a.timestamp);
  });
  const top10 = scores.slice(0, 10);
  res.json({ success: true, leaderboard: top10 });
});

app.post('/api/scores', (req, res) => {
  const { name, score } = req.body;

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return res.status(400).json({ success: false, error: 'Player name is required' });
  }
  if (score === undefined || typeof score !== 'number' || !Number.isInteger(score) || score < 0) {
    return res.status(400).json({ success: false, error: 'Valid positive integer score is required' });
  }

  const scores = readScores();
  const newScore = {
    id: Date.now() + Math.random().toString(36).substr(2, 9),
    name: name.trim().substring(0, 50),
    score: score,
    timestamp: new Date().toISOString()
  };

  scores.push(newScore);
  const saved = writeScores(scores);

  if (!saved) {
    return res.status(500).json({ success: false, error: 'Failed to save score' });
  }

  res.status(201).json({ success: true, message: 'Score submitted successfully', score: newScore });
});

app.get('/api/scores', (req, res) => {
  const scores = readScores();
  res.json({ success: true, count: scores.length, scores: scores });
});

app.delete('/api/scores', (req, res) => {
  const success = writeScores([]);
  if (success) {
    res.json({ success: true, message: 'All scores cleared' });
  } else {
    res.status(500).json({ success: false, error: 'Failed to clear scores' });
  }
});

app.listen(PORT, () => {
  console.log('Leaderboard server running on http://localhost:' + PORT);
  console.log('API endpoints:');
  console.log('  GET    /api/leaderboard');
  console.log('  POST   /api/scores');
  console.log('  GET    /api/scores');
  console.log('  DELETE /api/scores');
});
SERVERJS

mkdir -p /app/data
echo '[]' > /app/data/scores.json

cat <<-DOCKERFILE > /app/Dockerfile
FROM node:18
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
DOCKERFILE

cd /app
docker build -t backend .
docker run -d -p 3000:3000 --name backend backend