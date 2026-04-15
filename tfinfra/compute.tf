resource "google_compute_instance" "vm_backend" {
  name         = "vm-backend"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_backend.id
    access_config {}
  }

  metadata_startup_script = <<-EOF
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
    cat <<'EOF' > /app/package.json
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
    EOF

    cat <<'EOF' > /app/server.js
    const express = require('express');
    const cors = require('cors');
    const fs = require('fs');
    const path = require('path');

    const app = express();
    const PORT = process.env.PORT || 3000;
    const DATA_FILE = path.join(__dirname, 'data', 'scores.json');

    // Middleware
    app.use(cors());
    app.use(express.json());

    // Ensure data directory exists
    const dataDir = path.join(__dirname, 'data');
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }

    // Initialize scores file if it doesn't exist
    if (!fs.existsSync(DATA_FILE)) {
      fs.writeFileSync(DATA_FILE, JSON.stringify([]));
    }

    // Helper: Read scores from file
    function readScores() {
      try {
        const data = fs.readFileSync(DATA_FILE, 'utf8');
        return JSON.parse(data);
      } catch (err) {
        console.error('Error reading scores:', err);
        return [];
      }
    }

    // Helper: Write scores to file
    function writeScores(scores) {
      try {
        fs.writeFileSync(DATA_FILE, JSON.stringify(scores, null, 2));
        return true;
      } catch (err) {
        console.error('Error writing scores:', err);
        return false;
      }
    }

    // GET /api/leaderboard - Retrieve top 10 scores
    app.get('/api/leaderboard', (req, res) => {
      const scores = readScores();
      // Sort by score descending, then by date (newest first for ties)
      scores.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        return new Date(b.timestamp) - new Date(a.timestamp);
      });
      const top10 = scores.slice(0, 10);
      res.json({ success: true, leaderboard: top10 });
    });

    // POST /api/scores - Submit a new score
    app.post('/api/scores', (req, res) => {
      const { name, score } = req.body;

      // Validation
      if (!name || typeof name !== 'string' || name.trim().length === 0) {
        return res.status(400).json({ success: false, error: 'Player name is required' });
      }
      if (score === undefined || typeof score !== 'number' || !Number.isInteger(score) || score < 0) {
        return res.status(400).json({ success: false, error: 'Valid positive integer score is required' });
      }

      const scores = readScores();
      const newScore = {
        id: Date.now() + Math.random().toString(36).substr(2, 9),
        name: name.trim().substring(0, 50), // Limit name length
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

    // GET /api/scores - Get all scores (optional, for debugging/admin)
    app.get('/api/scores', (req, res) => {
      const scores = readScores();
      res.json({ success: true, count: scores.length, scores: scores });
    });

    // DELETE /api/scores - Clear all scores (optional, for admin/reset)
    app.delete('/api/scores', (req, res) => {
      const success = writeScores([]);
      if (success) {
        res.json({ success: true, message: 'All scores cleared' });
      } else {
        res.status(500).json({ success: false, error: 'Failed to clear scores' });
      }
    });

    // Start server
    app.listen(PORT, () => {
      console.log(`Leaderboard server running on http://localhost:${PORT}`);
      console.log(`API endpoints:`);
      console.log(`  GET    /api/leaderboard`);
      console.log(`  POST   /api/scores`);
      console.log(`  GET    /api/scores`);
      console.log(`  DELETE /api/scores`);
    });
    EOF

    mkdir -p /app/data
    echo '[]' > /app/data/scores.json

    cat <<'EOF' > /app/Dockerfile
    FROM node:18
    WORKDIR /app
    COPY package.json .
    RUN npm install
    COPY . .
    EXPOSE 3000
    CMD ["node", "server.js"]
    EOF

    cd /app
    docker build -t backend .
    docker run -d -p 3000:3000 --name backend backend
  EOF

  tags = ["backend"]
}

resource "google_compute_instance" "vm_frontend" {
  name         = "vm-frontend"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_frontend.id
    access_config {}
  }

  metadata_startup_script = <<-EOF
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
    cat <<'EOF' > /app/index.html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="X-UA-Compatible" content="IE=edge" />
    <meta name="viewport" content="width=device-width,user-scalable=no" />
    <script src="https://codepen.io/steveg3003/pen/zBVakw"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r83/three.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/latest/TweenMax.min.js"></script>
    <title>Talha - Tower Blocks</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <script src="script.js" async></script>
    <div id="container">
      <div id="game"></div>
      <div id="score">0</div>
      <div id="instructions">
        Click (or press the spacebar) to place the block
      </div>
      <div class="game-over">
        <h2>Game Over</h2>
        <p>You did great, you're the best.</p>
        <p>Click or spacebar to start again</p>
      </div>
      <div class="game-ready">
        <div id="start-button">Start</div>
        <div></div>
      </div>

      <!-- Name Input Modal (shown on game over) -->
      <div class="name-input-modal">
        <div class="modal-content">
          <h2>Game Over!</h2>
          <p>Your score: <span id="final-score">0</span></p>
          <div class="input-group">
            <input type="text" id="player-name" placeholder="Enter your name" maxlength="20" autocomplete="off">
            <button id="submit-score-btn">Submit</button>
          </div>
          <p class="error-message" id="name-error"></p>
          <button class="skip-btn" id="skip-submit">Skip</button>
        </div>
      </div>

      <!-- Leaderboard Modal -->
      <div class="leaderboard-modal">
        <div class="modal-content">
          <div class="leaderboard-header">
            <h2>Leaderboard</h2>
            <button class="close-btn" id="close-leaderboard">&times;</button>
          </div>
          <div class="leaderboard-list" id="leaderboard-list">
            <!-- Populated by JavaScript -->
          </div>
        </div>
      </div>
    </div>
  </body>
</html>
EOF

    cat <<'EOF' > /app/style.css
@import url("https://fonts.googleapis.com/css?family=Comfortaa");
html,
body {
  margin: 0;
  overflow: hidden;
  height: 100%;
  width: 100%;
  position: relative;
  font-family: "Comfortaa", cursive;
}
#container {
  width: 100%;
  height: 100%;
}
#container #score {
  position: absolute;
  top: 20px;
  width: 100%;
  text-align: center;
  font-size: 10vh;
  transition: transform 0.5s ease;
  color: #334;
  transform: translatey(-200px) scale(1);
}
#container #game {
  position: absolute;
  top: 0;
  right: 0;
  bottom: 0;
  left: 0;
}
#container .game-over {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 85%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
#container .game-over * {
  transition: opacity 0.5s ease, transform 0.5s ease;
  opacity: 0;
  transform: translatey(-50px);
  color: #334;
}
#container .game-over h2 {
  margin: 0;
  padding: 0;
  font-size: 40px;
}
#container .game-ready {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: space-around;
}
#container .game-ready #start-button {
  transition: opacity 0.5s ease, transform 0.5s ease;
  opacity: 0;
  transform: translatey(-50px);
  border: 3px solid #334;
  padding: 10px 20px;
  background-color: transparent;
  color: #334;
  font-size: 30px;
}
#container #instructions {
  position: absolute;
  width: 100%;
  top: 16vh;
  left: 0;
  text-align: center;
  transition: opacity 0.5s ease, transform 0.5s ease;
  opacity: 0;
}
#container #instructions.hide {
  opacity: 0 !important;
}
#container.playing #score,
#container.resetting #score {
  transform: translatey(0px) scale(1);
}
#container.playing #instructions {
  opacity: 1;
}
#container.ready .game-ready #start-button {
  opacity: 1;
  transform: translatey(0);
}
#container.ended #score {
  transform: translatey(6vh) scale(1.5);
}
#container.ended .game-over * {
  opacity: 1;
  transform: translatey(0);
}
#container.ended .game-over p {
  transition-delay: 0.3s;
}

/* Modal Overlay (shared by both modals) */
.name-input-modal,
.leaderboard-modal {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(51, 51, 68, 0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.3s ease;
}
.name-input-modal.active,
.leaderboard-modal.active {
  opacity: 1;
  pointer-events: auto;
}

/* Modal Content Box */
.modal-content {
  background-color: #D0CBC7;
  padding: 40px;
  border-radius: 10px;
  text-align: center;
  max-width: 400px;
  width: 90%;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
  transform: translateY(-20px);
  transition: transform 0.3s ease;
}
.name-input-modal.active .modal-content,
.leaderboard-modal.active .modal-content {
  transform: translateY(0);
}

/* Modal Typography */
.modal-content h2 {
  margin: 0 0 15px 0;
  color: #334;
  font-size: 28px;
}
.modal-content p {
  color: #334;
  font-size: 16px;
  margin: 10px 0;
}

/* Name Input Group */
.input-group {
  display: flex;
  gap: 10px;
  margin: 20px 0;
}
.input-group input {
  flex: 1;
  padding: 12px 15px;
  border: 2px solid #334;
  border-radius: 5px;
  font-family: "Comfortaa", cursive;
  font-size: 16px;
  background-color: #fff;
  color: #334;
  outline: none;
  transition: border-color 0.2s;
}
.input-group input:focus {
  border-color: #556;
}
.input-group button {
  padding: 12px 25px;
  background-color: #334;
  color: #D0CBC7;
  border: none;
  border-radius: 5px;
  font-family: "Comfortaa", cursive;
  font-size: 16px;
  cursor: pointer;
  transition: background-color 0.2s, transform 0.1s;
}
.input-group button:hover {
  background-color: #445;
  transform: scale(1.05);
}
.input-group button:active {
  transform: scale(0.95);
}

/* Skip Button */
.skip-btn {
  background: none;
  border: none;
  color: #667788;
  font-family: "Comfortaa", cursive;
  font-size: 14px;
  cursor: pointer;
  margin-top: 10px;
  text-decoration: underline;
  transition: color 0.2s;
}
.skip-btn:hover {
  color: #334;
}

/* Error Message */
.error-message {
  color: #c44;
  font-size: 14px;
  min-height: 20px;
  margin: 5px 0 0 0;
}

/* Leaderboard Header */
.leaderboard-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}
.leaderboard-header h2 {
  margin: 0;
}

/* Close Button */
.close-btn {
  background: none;
  border: none;
  font-size: 32px;
  color: #334;
  cursor: pointer;
  line-height: 1;
  padding: 0;
  width: 32px;
  height: 32px;
  transition: color 0.2s;
}
.close-btn:hover {
  color: #c44;
}

/* Leaderboard List */
.leaderboard-list {
  max-height: 60vh;
  overflow-y: auto;
  text-align: left;
}

/* Individual Leaderboard Entry */
.leaderboard-entry {
  display: flex;
  align-items: center;
  padding: 12px 15px;
  margin-bottom: 8px;
  background-color: rgba(255, 255, 255, 0.5);
  border-radius: 6px;
  border-left: 4px solid #334;
  transition: transform 0.2s, background-color 0.2s;
}
.leaderboard-entry:hover {
  background-color: rgba(255, 255, 255, 0.8);
  transform: translateX(5px);
}
.leaderboard-entry.top-rank {
  background-color: rgba(51, 51, 68, 0.1);
  border-left-color: #d4a;
}
.leaderboard-entry.current-player {
  background-color: rgba(51, 51, 68, 0.15);
  border-left-color: #4a4;
}

.rank {
  font-size: 20px;
  font-weight: bold;
  color: #334;
  min-width: 40px;
  text-align: center;
}
.player-name {
  flex: 1;
  font-size: 16px;
  color: #334;
  margin-left: 10px;
}
.player-score {
  font-size: 18px;
  font-weight: bold;
  color: #334;
}
.player-date {
  font-size: 12px;
  color: #667788;
  margin-left: 10px;
}

/* Empty State */
.leaderboard-empty {
  text-align: center;
  color: #667788;
  font-style: italic;
  padding: 30px;
}

/* Scrollbar Styling */
.leaderboard-list::-webkit-scrollbar {
  width: 8px;
}
.leaderboard-list::-webkit-scrollbar-track {
  background: rgba(51, 51, 68, 0.1);
  border-radius: 4px;
}
.leaderboard-list::-webkit-scrollbar-thumb {
  background: #334;
  border-radius: 4px;
}
.leaderboard-list::-webkit-scrollbar-thumb:hover {
  background: #445;
}

/* Responsive adjustments */
@media (max-width: 600px) {
  .modal-content {
    padding: 25px;
    margin: 20px;
  }
  .input-group {
    flex-direction: column;
  }
  .input-group button {
    width: 100%;
  }
}
EOF

    cat <<'EOF' > /app/script.js
console.clear();

// API Configuration
const API_BASE_URL = 'http://10.0.2.2:3000/api';

// Helper: Submit score to backend
async function submitScore(name, score) {
  try {
    const response = await fetch(`${API_BASE_URL}/scores`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, score })
    });
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error submitting score:', error);
    return { success: false, error: 'Network error' };
  }
}

// Helper: Fetch leaderboard from backend
async function fetchLeaderboard() {
  try {
    const response = await fetch(`${API_BASE_URL}/leaderboard`);
    const data = await response.json();
    return data.success ? data.leaderboard : [];
  } catch (error) {
    console.error('Error fetching leaderboard:', error);
    return [];
  }
}

// Helper: Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

var Stage = /** @class */ (function () {
  function Stage() {
    // container
    var _this = this;
    this.render = function () {
      this.renderer.render(this.scene, this.camera);
    };
    this.add = function (elem) {
      this.scene.add(elem);
    };
    this.remove = function (elem) {
      this.scene.remove(elem);
    };
    this.container = document.getElementById("game");
    // renderer
    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: false,
    });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setClearColor("#D0CBC7", 1);
    this.container.appendChild(this.renderer.domElement);
    // scene
    this.scene = new THREE.Scene();
    // camera
    var aspect = window.innerWidth / window.innerHeight;
    var d = 20;
    this.camera = new THREE.OrthographicCamera(
      -d * aspect,
      d * aspect,
      d,
      -d,
      -100,
      1000
    );
    this.camera.position.x = 2;
    this.camera.position.y = 2;
    this.camera.position.z = 2;
    this.camera.lookAt(new THREE.Vector3(0, 0, 0));
    //light
    this.light = new THREE.DirectionalLight(0xffffff, 0.5);
    this.light.position.set(0, 499, 0);
    this.scene.add(this.light);
    this.softLight = new THREE.AmbientLight(0xffffff, 0.4);
    this.scene.add(this.softLight);
    window.addEventListener("resize", function () {
      return _this.onResize();
    });
    this.onResize();
  }
  Stage.prototype.setCamera = function (y, speed) {
    if (speed === void 0) {
      speed = 0.3;
    }
    TweenLite.to(this.camera.position, speed, {
      y: y + 4,
      ease: Power1.easeInOut,
    });
    TweenLite.to(this.camera.lookAt, speed, { y: y, ease: Power1.easeInOut });
  };
  Stage.prototype.onResize = function () {
    var viewSize = 30;
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.camera.left = window.innerWidth / -viewSize;
    this.camera.right = window.innerWidth / viewSize;
    this.camera.top = window.innerHeight / viewSize;
    this.camera.bottom = window.innerHeight / -viewSize;
    this.camera.updateProjectionMatrix();
  };
  return Stage;
})();

var Block = /** @class */ (function () {
  function Block(block) {
    // set size and position
    this.STATES = { ACTIVE: "active", STOPPED: "stopped", MISSED: "missed" };
    this.MOVE_AMOUNT = 12;
    this.dimension = { width: 0, height: 0, depth: 0 };
    this.position = { x: 0, y: 0, z: 0 };
    this.targetBlock = block;
    this.index = (this.targetBlock ? this.targetBlock.index : 0) + 1;
    this.workingPlane = this.index % 2 ? "x" : "z";
    this.workingDimension = this.index % 2 ? "width" : "depth";
    // set the dimensions from the target block, or defaults.
    this.dimension.width = this.targetBlock
      ? this.targetBlock.dimension.width
      : 10;
    this.dimension.height = this.targetBlock
      ? this.targetBlock.dimension.height
      : 2;
    this.dimension.depth = this.targetBlock
      ? this.targetBlock.dimension.depth
      : 10;
    this.position.x = this.targetBlock ? this.targetBlock.position.x : 0;
    this.position.y = this.dimension.height * this.index;
    this.position.z = this.targetBlock ? this.targetBlock.position.z : 0;
    this.colorOffset = this.targetBlock
      ? this.targetBlock.colorOffset
      : Math.round(Math.random() * 100);
    // set color
    if (!this.targetBlock) {
      this.color = 0x333344;
    } else {
      var offset = this.index + this.colorOffset;
      var r = Math.sin(0.3 * offset) * 55 + 200;
      var g = Math.sin(0.3 * offset + 2) * 55 + 200;
      var b = Math.sin(0.3 * offset + 4) * 55 + 200;
      this.color = new THREE.Color(r / 255, g / 255, b / 255);
    }
    // state
    this.state = this.index > 1 ? this.STATES.ACTIVE : this.STATES.STOPPED;
    // set direction
    this.speed = -0.1 - this.index * 0.005;
    if (this.speed < -4) this.speed = -4;
    this.direction = this.speed;
    // create block
    var geometry = new THREE.BoxGeometry(
      this.dimension.width,
      this.dimension.height,
      this.dimension.depth
    );
    geometry.applyMatrix(
      new THREE.Matrix4().makeTranslation(
        this.dimension.width / 2,
        this.dimension.height / 2,
        this.dimension.depth / 2
      )
    );
    this.material = new THREE.MeshToonMaterial({
      color: this.color,
      shading: THREE.FlatShading,
    });
    this.mesh = new THREE.Mesh(geometry, this.material);
    this.mesh.position.set(
      this.position.x,
      this.position.y + (this.state == this.STATES.ACTIVE ? 0 : 0),
      this.position.z
    );
    if (this.state == this.STATES.ACTIVE) {
      this.position[this.workingPlane] =
        Math.random() > 0.5 ? -this.MOVE_AMOUNT : this.MOVE_AMOUNT;
    }
  }
  Block.prototype.reverseDirection = function () {
    this.direction = this.direction > 0 ? this.speed : Math.abs(this.speed);
  };
  Block.prototype.place = function () {
    this.state = this.STATES.STOPPED;
    var overlap =
      this.targetBlock.dimension[this.workingDimension] -
      Math.abs(
        this.position[this.workingPlane] -
          this.targetBlock.position[this.workingPlane]
      );
    var blocksToReturn = {
      plane: this.workingPlane,
      direction: this.direction,
    };
    if (this.dimension[this.workingDimension] - overlap < 0.3) {
      overlap = this.dimension[this.workingDimension];
      blocksToReturn.bonus = true;
      this.position.x = this.targetBlock.position.x;
      this.position.z = this.targetBlock.position.z;
      this.dimension.width = this.targetBlock.dimension.width;
      this.dimension.depth = this.targetBlock.dimension.depth;
    }
    if (overlap > 0) {
      var choppedDimensions = {
        width: this.dimension.width,
        height: this.dimension.height,
        depth: this.dimension.depth,
      };
      choppedDimensions[this.workingDimension] -= overlap;
      this.dimension[this.workingDimension] = overlap;
      var placedGeometry = new THREE.BoxGeometry(
        this.dimension.width,
        this.dimension.height,
        this.dimension.depth
      );
      placedGeometry.applyMatrix(
        new THREE.Matrix4().makeTranslation(
          this.dimension.width / 2,
          this.dimension.height / 2,
          this.dimension.depth / 2
        )
      );
      var placedMesh = new THREE.Mesh(placedGeometry, this.material);
      var choppedGeometry = new THREE.BoxGeometry(
        choppedDimensions.width,
        choppedDimensions.height,
        choppedDimensions.depth
      );
      choppedGeometry.applyMatrix(
        new THREE.Matrix4().makeTranslation(
          choppedDimensions.width / 2,
          choppedDimensions.height / 2,
          choppedDimensions.depth / 2
        )
      );
      var choppedMesh = new THREE.Mesh(choppedGeometry, this.material);
      var choppedPosition = {
        x: this.position.x,
        y: this.position.y,
        z: this.position.z,
      };
      if (
        this.position[this.workingPlane] <
        this.targetBlock.position[this.workingPlane]
      ) {
        this.position[this.workingPlane] = this.targetBlock.position[
          this.workingPlane
        ];
      } else {
        choppedPosition[this.workingPlane] += overlap;
      }
      placedMesh.position.set(
        this.position.x,
        this.position.y,
        this.position.z
      );
      choppedMesh.position.set(
        choppedPosition.x,
        choppedPosition.y,
        choppedPosition.z
      );
      blocksToReturn.placed = placedMesh;
      if (!blocksToReturn.bonus) blocksToReturn.chopped = choppedMesh;
    } else {
      this.state = this.STATES.MISSED;
    }
    this.dimension[this.workingDimension] = overlap;
    return blocksToReturn;
  };
  Block.prototype.tick = function () {
    if (this.state == this.STATES.ACTIVE) {
      var value = this.position[this.workingPlane];
      if (value > this.MOVE_AMOUNT || value < -this.MOVE_AMOUNT)
        this.reverseDirection();
      this.position[this.workingPlane] += this.direction;
      this.mesh.position[this.workingPlane] = this.position[this.workingPlane];
    }
  };
  return Block;
})();

var Game = /** @class */ (function () {
  function Game() {
    var _this = this;
    this.STATES = {
      LOADING: "loading",
      PLAYING: "playing",
      READY: "ready",
      ENDED: "ended",
      RESETTING: "resetting",
    };
    this.blocks = [];
    this.state = this.STATES.LOADING;
    this.stage = new Stage();
    this.playerName = '';
    this.lastSubmittedName = '';
    this.finalScore = 0;
    this.mainContainer = document.getElementById("container");
    this.scoreContainer = document.getElementById("score");
    this.startButton = document.getElementById("start-button");
    this.instructions = document.getElementById("instructions");
    this.scoreContainer.innerHTML = "0";
    this.newBlocks = new THREE.Group();
    this.placedBlocks = new THREE.Group();
    this.choppedBlocks = new THREE.Group();
    this.stage.add(this.newBlocks);
    this.stage.add(this.placedBlocks);
    this.stage.add(this.choppedBlocks);
    this.addBlock();
    this.tick();
    this.showNameInput(null, true);
    document.addEventListener("keydown", function (e) {
      if (e.keyCode == 32) _this.onAction();
    });
    document.addEventListener("click", function (e) {
      _this.onAction();
    });
    document.addEventListener("touchstart", function (e) {
      // Prevent default only if no modals are active to allow modal interactions on mobile
      if (!document.querySelector('.name-input-modal.active, .leaderboard-modal.active')) {
        e.preventDefault();
      }
    });

    // Name input modal events
    document.getElementById('submit-score-btn').addEventListener('click', function () {
      var name = document.getElementById('player-name').value;
      _this.submitScore(name);
    });
    document.getElementById('player-name').addEventListener('keypress', function (e) {
      if (e.key === 'Enter') {
        _this.submitScore(document.getElementById('player-name').value);
      }
    });
    document.getElementById('skip-submit').addEventListener('click', function () {
      _this.hideNameInput();
    });

    // Leaderboard modal events
    document.getElementById('close-leaderboard').addEventListener('click', function () {
      _this.hideLeaderboard();
    });

    // Close modals on overlay click
    document.querySelectorAll('.name-input-modal, .leaderboard-modal').forEach(modal => {
      modal.addEventListener('click', function (e) {
        if (e.target === modal) {
          modal.classList.remove('active');
        }
      });
    });
  }
  Game.prototype.updateState = function (newState) {
    for (var key in this.STATES)
      this.mainContainer.classList.remove(this.STATES[key]);
    this.mainContainer.classList.add(newState);
    this.state = newState;
  };
  Game.prototype.onAction = function () {
    switch (this.state) {
      case this.STATES.READY:
        this.startGame();
        break;
      case this.STATES.PLAYING:
        this.placeBlock();
        break;
      case this.STATES.ENDED:
        this.restartGame();
        break;
    }
  };
  Game.prototype.startGame = function () {
    if (this.state != this.STATES.PLAYING) {
      this.scoreContainer.innerHTML = "0";
      this.updateState(this.STATES.PLAYING);
      this.addBlock();
    }
  };
  Game.prototype.restartGame = function () {
    var _this = this;
    this.updateState(this.STATES.RESETTING);
    var oldBlocks = this.placedBlocks.children;
    var removeSpeed = 0.2;
    var delayAmount = 0.02;
    var _loop_1 = function (i) {
      TweenLite.to(oldBlocks[i].scale, removeSpeed, {
        x: 0,
        y: 0,
        z: 0,
        delay: (oldBlocks.length - i) * delayAmount,
        ease: Power1.easeIn,
        onComplete: function () {
          return _this.placedBlocks.remove(oldBlocks[i]);
        },
      });
      TweenLite.to(oldBlocks[i].rotation, removeSpeed, {
        y: 0.5,
        delay: (oldBlocks.length - i) * delayAmount,
        ease: Power1.easeIn,
      });
    };
    for (var i = 0; i < oldBlocks.length; i++) {
      _loop_1(i);
    }
    var cameraMoveSpeed = removeSpeed * 2 + oldBlocks.length * delayAmount;
    this.stage.setCamera(2, cameraMoveSpeed);
    var countdown = { value: this.blocks.length - 1 };
    TweenLite.to(countdown, cameraMoveSpeed, {
      value: 0,
      onUpdate: function () {
        _this.scoreContainer.innerHTML = String(Math.round(countdown.value));
      },
    });
    this.blocks = this.blocks.slice(0, 1);
    setTimeout(function () {
      _this.startGame();
    }, cameraMoveSpeed * 1000);
  };
  Game.prototype.placeBlock = function () {
    var _this = this;
    var currentBlock = this.blocks[this.blocks.length - 1];
    var newBlocks = currentBlock.place();
    this.newBlocks.remove(currentBlock.mesh);
    if (newBlocks.placed) this.placedBlocks.add(newBlocks.placed);
    if (newBlocks.chopped) {
      this.choppedBlocks.add(newBlocks.chopped);
      var positionParams = {
        y: "-=30",
        ease: Power1.easeIn,
        onComplete: function () {
          return _this.choppedBlocks.remove(newBlocks.chopped);
        },
      };
      var rotateRandomness = 10;
      var rotationParams = {
        delay: 0.05,
        x:
          newBlocks.plane == "z"
            ? Math.random() * rotateRandomness - rotateRandomness / 2
            : 0.1,
        z:
          newBlocks.plane == "x"
            ? Math.random() * rotateRandomness - rotateRandomness / 2
            : 0.1,
        y: Math.random() * 0.1,
      };
      if (
        newBlocks.chopped.position[newBlocks.plane] >
        newBlocks.placed.position[newBlocks.plane]
      ) {
        positionParams[newBlocks.plane] =
          "+=" + 40 * Math.abs(newBlocks.direction);
      } else {
        positionParams[newBlocks.plane] =
          "-=" + 40 * Math.abs(newBlocks.direction);
      }
      TweenLite.to(newBlocks.chopped.position, 1, positionParams);
      TweenLite.to(newBlocks.chopped.rotation, 1, rotationParams);
    }
    this.addBlock();
  };
  Game.prototype.addBlock = function () {
    var lastBlock = this.blocks[this.blocks.length - 1];
    if (lastBlock && lastBlock.state == lastBlock.STATES.MISSED) {
      return this.endGame();
    }
    this.scoreContainer.innerHTML = String(this.blocks.length - 1);
    var newKidOnTheBlock = new Block(lastBlock);
    this.newBlocks.add(newKidOnTheBlock.mesh);
    this.blocks.push(newKidOnTheBlock);
    this.stage.setCamera(this.blocks.length * 2);
    if (this.blocks.length >= 5) this.instructions.classList.add("hide");
  };
  Game.prototype.endGame = function () {
    this.updateState(this.STATES.ENDED);
    // Auto-submit score
    this.finalScore = this.blocks.length - 1;
    this.submitScore(this.playerName);
  };

  Game.prototype.showNameInput = function (score, isInitial) {
    var _this = this;
    if (isInitial) {
      this.finalScore = 0;
      document.querySelector('.modal-content h2').textContent = 'Enter Your Name';
      document.getElementById('final-score').parentElement.style.display = 'none';
      document.getElementById('submit-score-btn').textContent = 'Start Game';
      document.getElementById('skip-submit').style.display = 'none';
    } else {
      this.finalScore = score;
      document.querySelector('.modal-content h2').textContent = 'Game Over!';
      document.getElementById('final-score').textContent = score;
      document.getElementById('final-score').parentElement.style.display = 'block';
      document.getElementById('submit-score-btn').textContent = 'Submit';
      document.getElementById('skip-submit').style.display = 'block';
    }
    document.getElementById('player-name').value = '';
    document.getElementById('name-error').textContent = '';
    document.querySelector('.name-input-modal').classList.add('active');
    document.getElementById('player-name').focus();
  };

  Game.prototype.hideNameInput = function () {
    document.querySelector('.name-input-modal').classList.remove('active');
  };

  Game.prototype.submitScore = async function (playerName) {
    var _this = this;
    const name = playerName.trim();
    if (!name) {
      document.getElementById('name-error').textContent = 'Please enter your name';
      return;
    }

    if (this.finalScore > 0) {
      // Game over: submit score
      const result = await submitScore(name, this.finalScore);
      if (result.success) {
        this.lastSubmittedName = name;
        this.hideNameInput();
        this.showLeaderboard();
      } else {
        document.getElementById('name-error').textContent = result.error || 'Failed to submit score';
      }
    } else {
      // Initial: store name and proceed to ready
      this.playerName = name;
      this.hideNameInput();
      this.updateState(this.STATES.READY);
    }
  };

  Game.prototype.showLeaderboard = function () {
    this.updateLeaderboardDisplay();
    document.querySelector('.leaderboard-modal').classList.add('active');
  };

  Game.prototype.hideLeaderboard = function () {
    document.querySelector('.leaderboard-modal').classList.remove('active');
  };

  Game.prototype.updateLeaderboardDisplay = async function () {
    var _this = this;
    const leaderboard = await fetchLeaderboard();
    const listContainer = document.getElementById('leaderboard-list');

    if (leaderboard.length === 0) {
      listContainer.innerHTML = '<div class="leaderboard-empty">No scores yet. Be the first!</div>';
      return;
    }

    const entries = leaderboard.map((entry, index) => {
      const rank = index + 1;
      const date = new Date(entry.timestamp).toLocaleDateString();
      const isTop3 = rank <= 3;
      const isCurrentPlayer = entry.name === this.lastSubmittedName && entry.score === this.finalScore;

      return `
        <div class="leaderboard-entry ${isTop3 ? 'top-rank' : ''} ${isCurrentPlayer ? 'current-player' : ''}">
          <span class="rank">#${rank}</span>
          <span class="player-name">${escapeHtml(entry.name)}</span>
          <span class="player-score">${entry.score}</span>
          <span class="player-date">${date}</span>
        </div>
      `;
    }).join('');

    listContainer.innerHTML = entries;
  };

  Game.prototype.tick = function () {
    var _this = this;
    // Only update blocks if game is in playing state and name modal is not active
    if (this.state === this.STATES.PLAYING && !document.querySelector('.name-input-modal').classList.contains('active')) {
      this.blocks[this.blocks.length - 1].tick();
    }
    this.stage.render();
    requestAnimationFrame(function () {
      _this.tick();
    });
  };
  return Game;
})();
var game = new Game();
EOF

    mkdir -p /app/sound
    cat <<'EOF' > /app/sound/placeholder.txt
Sound files would be copied here
EOF

    cat <<'EOF' > /app/Dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
COPY style.css /usr/share/nginx/html/
COPY script.js /usr/share/nginx/html/
COPY sound /usr/share/nginx/html/sound/
EXPOSE 80
EOF

    cd /app
    docker build -t frontend .
    docker run -d -p 80:80 --name frontend frontend
  EOF

  tags = ["frontend"]
  depends_on = [google_compute_instance.vm_backend]
}