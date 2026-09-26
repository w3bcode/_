// ai.js - ES6 Node.js OOP Event-Indexed Autonomous Local AI Kernel
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { execSync } from 'child_process';
import os from 'os';

class LlamaRuntime {
    constructor(modelPath, threads = 8, ctx = 4096, predict = 512) {
        this.modelPath = modelPath;
        this.threads = threads;
        this.ctx = ctx;
        this.predict = predict;
        // Detect subcommand-style binary vs single-purpose binary
        this.llamaBase = "llama"; 
    }

    run(prompt) {
        if (!fs.existsSync(this.modelPath)) {
            throw new Error(`Model not found: ${this.modelPath}`);
        }

        // Pass prompt via temporary file for cross-version safety
        const tmpFile = path.join(os.tmpdir(), `ai.prompt.${crypto.randomBytes(4).toString('hex')}`);
        fs.writeFileSync(tmpFile, prompt, 'utf8');

        const cmd = `${this.llamaBase} cli -m "${this.modelPath}" -t ${this.threads} -c ${this.ctx} -n ${this.predict} -f "${tmpFile}"`;
        
        try {
            const output = execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            fs.unlinkSync(tmpFile);
            return output;
        } catch (error) {
            fs.unlinkSync(tmpFile);
            throw new Error(`LLAMA_ERROR: rc=${error.status} stderr=${error.stderr?.substring(0, 400)}`);
        }
    }
}

class EventLedger {
    constructor(dbDir) {
        this.eventLog = path.join(dbDir, 'events.jsonl');
        this.seqFile = path.join(dbDir, 'event.seq');
        this.headFile = path.join(dbDir, 'head');
        this.eventDir = path.join(dbDir, 'events');
        
        if (!fs.existsSync(this.eventDir)) fs.mkdirSync(this.eventDir, { recursive: true });
    }

    nextSeq() {
        let seq = 0;
        if (fs.existsSync(this.seqFile)) {
            seq = parseInt(fs.readFileSync(this.seqFile, 'utf8'), 10) || 0;
        }
        seq += 1;
        fs.writeFileSync(this.seqFile, seq.toString(), 'utf8');
        return seq;
    }

    getHead() {
        return fs.existsSync(this.headFile) ? fs.readFileSync(this.headFile, 'utf8').trim() : "";
    }

    registerEvent(type, filePath, action, result, parent, payload, stateSha) {
        const seq = this.nextSeq();
        const ts = new Date().toISOString();
        
        const canonical = `${seq}\n${ts}\n${type}\n${parent}\n${filePath}\n${action}\n${result}\n${stateSha}\n${payload}\n${this.getHead()}`;
        const eventId = crypto.createHash('sha256').update(canonical).digest('hex');
        
        const eventData = {
            soap: "1",
            event: { id: eventId, parent, timestamp: ts, seq, type },
            state: { path: filePath, sha256: stateSha },
            observation: { result, payload },
            action: { op: action, path: filePath },
            proof: { canonical_sha256: eventId }
        };

        const eventFilePath = path.join(this.eventDir, `${seq}-${eventId}.json`);
        fs.writeFileSync(eventFilePath, JSON.stringify(eventData, null, 2), 'utf8');
        fs.appendFileSync(this.eventLog, `${seq}\t${eventId}\t${type}\t${filePath}\t${ts}\n`, 'utf8');
        fs.writeFileSync(this.headFile, eventId, 'utf8');

        return eventId;
    }
}

class EntropyRegister {
    constructor() {
        // Bit index mapping:
        // 7: Convergence, 6: Executable, 5: Structural, 4: Relevance
        // 3: Novelty, 2: Potential, 1: Contradiction, 0: Entropy-cluster
        this.weights = {
            relevance: 0.25,
            structural: 0.20,
            novelty: 0.15,
            convergence: 0.15,
            executable: 0.10,
            quote: 0.05,
            potential: 0.05,
            contradiction: -0.05
        };
        
        this.delayedEntropy = { C: 1.0, K: 0.8, E: 0.5 };
    }

    calculateScore(metrics) {
        let score = (metrics.relevance * this.weights.relevance) +
                    (metrics.structural * this.weights.structural) +
                    (metrics.novelty * this.weights.novelty) +
                    (metrics.convergence * this.weights.convergence) +
                    (metrics.executable * this.weights.executable) +
                    (metrics.quote * this.weights.quote) +
                    (metrics.potential * this.weights.potential) +
                    (metrics.contradiction * this.weights.contradiction);
        
        score = Math.max(0, Math.min(1, score));
        return Math.round(score * 255);
    }

    calculateDelayedEntropy(step) {
        // Delayed entropy meta-rule: D[n+1] = C[n] * K[n] * E[n]
        const D = this.delayedEntropy.C * this.delayedEntropy.K * this.delayedEntropy.E;
        // R[n+2] = D[n+1] * K[n+2]
        const R = D * this.delayedEntropy.K;
        return { D, R };
    }
}

class FileIndexStorage {
    constructor(dbDir) {
        this.indexPath = path.join(dbDir, 'file_index.json');
        this.init();
    }

    init() {
        if (!fs.existsSync(this.indexPath)) {
            fs.writeFileSync(this.indexPath, JSON.stringify({ version: 1, events: [] }, null, 2));
        }
    }

    updateIndex(eventLogPath) {
        if (!fs.existsSync(eventLogPath)) return;
        
        const lines = fs.readFileSync(eventLogPath, 'utf8').trim().split('\n');
        const events = lines.map(line => {
            const [seq, id, type, path, timestamp] = line.split('\t');
            return { seq: parseInt(seq, 10), id, type, path, timestamp };
        });

        const indexData = {
            version: 1,
            generated: new Date().toISOString(),
            events
        };

        fs.writeFileSync(this.indexPath, JSON.stringify(indexData, null, 2), 'utf8');
    }
}

class AIKernel {
    constructor(homeDir = process.env.HOME || '/root') {
        this.aiHome = path.join(homeDir, '.ai');
        this.stateDir = path.join(this.aiHome, '.ai-state');
        this.dbDir = path.join(this.stateDir, 'db');
        
        fs.mkdirSync(this.dbDir, { recursive: true });

        this.ledger = new EventLedger(this.dbDir);
        this.index = new FileIndexStorage(this.dbDir);
        this.entropy = new EntropyRegister();
        
        const modelPath = process.env.AI_MODEL_PATH || path.join(this.aiHome, 'models', 'qwen2.5-coder-3b-instruct-q4_k_m.gguf');
        this.runtime = new LlamaRuntime(modelPath);

        this.stepCount = 0;
        this.poles = [
            'analytical', 'structural', 'implementation', 'adversarial',
            'recursive', 'diagnostic', 'exploratory', 'convergence'
        ];
    }

    step(request) {
        this.stepCount++;
        
        // Modulo 7 entropy viced versa init stepcounts
        let entropyMultiplier = 1;
        if (this.stepCount % 7 === 0) {
            entropyMultiplier = -1; // Viced versa flip on modulo 7
        }

        const delayedEnt = this.entropy.calculateDelayedEntropy(this.stepCount);
        const finalEntropyState = delayedEnt.D * entropyMultiplier;

        const parent = this.ledger.getHead();
        
        // 8-pole / 2Pi deterministic execution
        const poleIndex = this.stepCount % 8;
        const currentPole = this.poles[poleIndex];
        const angle = poleIndex * 45; // 2Pi / 8 mappings

        const prompt = `
[AI KERNEL OOP]
POLE=${poleIndex}/7
ANGLE=${angle} degrees
RAIL=${currentPole}
ENTROPY_STATE=${finalEntropyState.toFixed(4)}
OBJECTIVE:
${request}
`;
        
        console.log(`[AI] Executing step ${this.stepCount} (Pole: ${currentPole}) with modulo 7 entropy phase: ${entropyMultiplier}`);
        
        try {
            const result = this.runtime.run(prompt);
            
            // Registration & Telemetry
            const eventId = this.ledger.registerEvent('INFERENCE', '', 'observe', 'success', parent, result, '');
            this.index.updateIndex(this.ledger.eventLog);
            
            console.log(`[OK] Event Registered: ${eventId}`);
            return result;
        } catch (err) {
            console.error(`[ERROR] Execution failed: ${err.message}`);
            this.ledger.registerEvent('ERROR', '', 'observe', 'failure', parent, err.message, '');
        }
    }
}

// Execution initialization
if (import.meta.url === `file://${process.argv[1]}`) {
    const kernel = new AIKernel();
    const request = process.argv.slice(2).join(' ') || "Determine optimal state continuation.";
    kernel.step(request);
}

export default AIKernel;
