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

# 3. Create Frontend Files
cat <<-INDEXHTML > index.html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge" />
    <meta name="viewport" content="width=device-width,user-scalable=no" />
    <script src="https://codepen.io/steveg3003/pen/zBVakw"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r83/three.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/latest/TweenMax.min.js"></script>
    <title>Tower Blocks</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <script src="script.js" async></script>
    <div id="container">
      <div id="game"></div>
      <div id="score">0</div>
      <div id="instructions">Click to place the block</div>
      <div class="game-over">
        <h2>Game Over</h2>
        <p>You did great!</p>
      </div>
      <div class="game-ready"><div id="start-button">Start</div></div>
      <div class="name-input-modal">
        <div class="modal-content">
          <h2>Game Over!</h2>
          <p>Score: <span id="final-score">0</span></p>
          <div class="input-group">
            <input type="text" id="player-name" placeholder="Name" maxlength="20">
            <button id="submit-score-btn">Submit</button>
          </div>
          <p class="error-message" id="name-error"></p>
          <button class="skip-btn" id="skip-submit">Skip</button>
        </div>
      </div>
      <div class="leaderboard-modal">
        <div class="modal-content">
          <div class="leaderboard-header">
            <h2>Leaderboard</h2>
            <button class="close-btn" id="close-leaderboard">&times;</button>
          </div>
          <div class="leaderboard-list" id="leaderboard-list"></div>
        </div>
      </div>
    </div>
  </body>
</html>
INDEXHTML

cat <<-STYLES > style.css
@import url("https://fonts.googleapis.com/css?family=Comfortaa");
html, body { margin: 0; overflow: hidden; height: 100%; width: 100%; font-family: "Comfortaa", cursive; background-color: #D0CBC7; }
#container { width: 100%; height: 100%; position: relative; }
#score { position: absolute; top: 20px; width: 100%; text-align: center; font-size: 10vh; color: #334; z-index: 10; }
.name-input-modal, .leaderboard-modal { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(51, 51, 68, 0.9); display: none; align-items: center; justify-content: center; z-index: 1000; }
.name-input-modal.active, .leaderboard-modal.active { display: flex; }
.modal-content { background: #D0CBC7; padding: 40px; border-radius: 10px; text-align: center; width: 90%; max-width: 400px; }
.leaderboard-entry { display: flex; justify-content: space-between; padding: 10px; border-bottom: 1px solid #334; }
STYLES

cat <<-SCRIPT > script.js
console.log("Game Script Loaded");
const API_BASE_URL = 'http://10.0.2.2:3000/api';
// ... (Your game logic goes here) ...
SCRIPT

mkdir -p sound
echo "placeholder" > sound/placeholder.txt

# 4. Create Dockerfile using the "COPY ALL" method
cat <<-NGINXDF > Dockerfile
FROM nginx:alpine
COPY . /usr/share/nginx/html/
EXPOSE 80
NGINXDF

# 5. Build and Run Container
docker build -t frontend .
docker run -d -p 80:80 --name frontend frontend