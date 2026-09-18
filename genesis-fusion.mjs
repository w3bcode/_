#!/bin/env node

import { createServer } from 'http';
import { spawn } from 'child_process';
import { promises as fs } from 'fs';
import path from 'path';

// ============================================================================
// OOP ES6 Backend: Filebased Genesis State & Event Recorder
// ============================================================================
class GenesisDatabase {
    constructor(dbPath = './genesis-state.json') {
        this.dbPath = dbPath;
        this.state = { events: [], tokens: [], sequences: [] };
    }

    async init() {
        try {
            const data = await fs.readFile(this.dbPath, 'utf8');
            this.state = JSON.parse(data);
        } catch {
            await this.sync(); // Create if missing
        }
    }

    async sync() {
        await fs.writeFile(this.dbPath, JSON.stringify(this.state, null, 2), 'utf8');
    }

    async createRecord(payload) {
        this.state.events.push({ timestamp: Date.now(), ...payload });
        await this.sync();
        return payload;
    }
}

// ============================================================================
// Tokenstream Processor: JS-to-Python3 Hash Pipelining
// ============================================================================
class TokenProcessor {
    /**
     * Executes an inline Python 3 script to tokenize text, bind to 3 channels,
     * and calculate SHA-256 genesis hashes and entropy, matching local-AI methodologies.
     */
    static async process(naturalText) {
        return new Promise((resolve, reject) => {
            const pyScript = `
import collections, hashlib, json, math, re, sys

text = sys.argv[1]
if not text:
    print(json.dumps({"error": "Empty input"}))
    sys.exit(1)

# Genesis root setup
genesis = hashlib.sha256(text.encode()).hexdigest()[:16]
tokens = list(re.finditer(r"\\S+", text))

# Entropy evaluation
freq = collections.Counter(text)
n = max(1, len(text))
H = -sum((c/n)*math.log2(c/n) for c in freq.values())

items = []
for i, m in enumerate(tokens):
    tok = m.group(0)
    # Bind to exactly 3 channels
    channel = i % 3
    phase = (2 * math.pi * channel) / 3
    
    # Origin & Rehash cascading
    origin = hashlib.sha256(f"{genesis}|origin|{i}|{tok}".encode()).hexdigest()
    marker = hashlib.md5(f"{origin}|{i}".encode()).hexdigest()
    rehash = hashlib.sha256(f"{origin}|{marker}|{channel}".encode()).hexdigest()
    
    items.append({
        "index": i,
        "token": tok,
        "channel": channel,
        "phase": round(phase, 4),
        "entropy": round(H, 4),
        "origin_hash": origin[:12],
        "marker": marker[:8],
        "rehash": rehash[:12]
    })

output = {
    "genesis_hash": genesis,
    "system_entropy": round(H, 4),
    "token_count": len(items),
    "stream": items
}
print(json.dumps(output))
`;
            const pyProcess = spawn('python3', ['-', naturalText]);
            let output = '';

            pyProcess.stdout.on('data', (data) => output += data.toString());
            pyProcess.stderr.on('data', (data) => console.error(`[Py stderr]: ${data}`));
            pyProcess.on('close', (code) => {
                if (code === 0) {
                    try { resolve(JSON.parse(output)); } 
                    catch (e) { reject("JSON parse error from Python stdout"); }
                } else {
                    reject(`Python exited with code ${code}`);
                }
            });

            // Write the script to stdin to avoid temporary files, matching local CLI setups.
            pyProcess.stdin.write(pyScript);
            pyProcess.stdin.end();
        });
    }
}

// ============================================================================
// HTML5 Single-file UI: Glassmorphic IDE Step-Sequencer
// ============================================================================
const HTML_VIEW = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Genesis Token IDE</title>
    <style>
        :root { --bg: #0a0a0c; --glass: rgba(255, 255, 255, 0.05); --border: rgba(255,255,255,0.1); --text: #e2e2e2; --accent: #4a9eff; }
        body { margin: 0; font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--text); display: flex; flex-direction: column; height: 100vh; overflow: hidden; }
        header { padding: 1rem 2rem; border-bottom: 1px solid var(--border); background: var(--glass); backdrop-filter: blur(10px); }
        .container { display: flex; flex: 1; overflow: hidden; }
        .panel { flex: 1; padding: 2rem; overflow-y: auto; border-right: 1px solid var(--border); }
        textarea { width: 100%; height: 150px; background: rgba(0,0,0,0.3); color: var(--accent); border: 1px solid var(--border); padding: 1rem; font-family: monospace; border-radius: 8px; resize: none; }
        button { background: var(--accent); color: #000; border: none; padding: 0.75rem 1.5rem; border-radius: 6px; cursor: pointer; font-weight: bold; margin-top: 1rem; }
        button:hover { opacity: 0.9; }
        .sequencer-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 1rem; margin-top: 2rem; }
        .token-card { background: var(--glass); border: 1px solid var(--border); padding: 1rem; border-radius: 8px; font-family: monospace; font-size: 0.85rem; }
        .token-card.ch-0 { border-top: 3px solid #ff4a4a; }
        .token-card.ch-1 { border-top: 3px solid #4aff4a; }
        .token-card.ch-2 { border-top: 3px solid #4a4aff; }
        .hash-str { color: #888; font-size: 0.75rem; word-break: break-all; }
        .genesis-stats { margin-top: 1rem; padding: 1rem; background: var(--glass); border-radius: 8px; font-family: monospace; }
    </style>
</head>
<body>
    <header>
        <h2>3-Channel Genesis Token IDE</h2>
    </header>
    <div class="container">
        <div class="panel">
            <h3>Natural Text Input</h3>
            <textarea id="promptInput" placeholder="Enter text to sequence and tokenize..."></textarea>
            <button onclick="processStream()">Rebase Tokenstream</button>
            
            <div id="statsBox" class="genesis-stats" style="display:none;"></div>
        </div>
        <div class="panel" style="flex: 2; background: rgba(0,0,0,0.2);">
            <h3>Event Recorder & Step-Sequencer</h3>
            <div id="sequencer" class="sequencer-grid"></div>
        </div>
    </div>

    <script>
        async function processStream() {
            const text = document.getElementById('promptInput').value;
            if(!text) return;
            
            const res = await fetch('/api/fusion', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ text })
            });
            const data = await res.json();
            
            // Update Stats
            const stats = document.getElementById('statsBox');
            stats.style.display = 'block';
            stats.innerHTML = \`Genesis Hash: <span style="color:var(--accent)">\${data.genesis_hash}</span><br>
                               System Entropy: \${data.system_entropy}<br>
                               Total Tokens: \${data.token_count}\`;

            // Update Sequencer
            const seq = document.getElementById('sequencer');
            seq.innerHTML = data.stream.map(t => \`
                <div class="token-card ch-\${t.channel}">
                    <strong style="color:var(--accent); font-size: 1.1rem;">\${t.token}</strong>
                    <br>Channel: \${t.channel} | Phase: \${t.phase}
                    <hr style="border:0; border-top:1px solid rgba(255,255,255,0.1); margin: 0.5rem 0;">
                    <div class="hash-str">
                        Origin: \${t.origin_hash}<br>
                        Marker: \${t.marker}<br>
                        Rehash: \${t.rehash}
                    </div>
                </div>
            \`).join('');
        }
    </script>
</body>
</html>`;

// ============================================================================
// Server Orchestration
// ============================================================================
const db = new GenesisDatabase();

const server = createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(HTML_VIEW);
    } 
    else if (req.method === 'POST' && req.url === '/api/fusion') {
        let body = '';
        req.on('data', chunk => body += chunk.toString());
        req.on('end', async () => {
            try {
                const { text } = JSON.parse(body);
                // Preprocess and Pipe to Python
                const tokenData = await TokenProcessor.process(text);
                
                // Filebased CRUD event logging
                await db.createRecord({
                    genesis: tokenData.genesis_hash,
                    entropy: tokenData.system_entropy,
                    tokens: tokenData.token_count
                });

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(tokenData));
            } catch (err) {
                res.writeHead(500);
                res.end(JSON.stringify({ error: err.toString() }));
            }
        });
    } 
    else {
        res.writeHead(404);
        res.end('Not found');
    }
});

// Initialization
db.init().then(() => {
    server.listen(3033, () => {
        console.log('[Genesis System] Online at http://localhost:3033');
        console.log('[Channels] Bound to 3-Channel 2Pi Phase configuration');
        console.log('[Entropy] SHA-256 and MD5 multi-layer hashing primed');
    });
});

