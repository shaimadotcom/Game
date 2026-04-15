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

// Serve static files
app.use(express.static(path.resolve(__dirname, '..', 'frontend')));
app.use('/sound', express.static(path.resolve(__dirname, '..', 'sound')));
console.log('Static files served from:', path.resolve(__dirname, '..', 'frontend'));
console.log('Sound files served from:', path.resolve(__dirname, '..', 'sound'));

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
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Leaderboard server running on http://0.0.0.0:${PORT}`);
  console.log(`API endpoints:`);
  console.log(`  GET    /api/leaderboard`);
  console.log(`  POST   /api/scores`);
  console.log(`  GET    /api/scores`);
  console.log(`  DELETE /api/scores`);
});
