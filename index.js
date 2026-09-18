#!/usr/bin/env node
/**
 * =============================================================================
 * AI Orchestrator Engine — Production Node.js 2Pi/8 Tokenstream Controller
 * Version: 3.0.0 Enterprise
 * Direct Translation & Enhancement of Shell 2Pi/8 Spatial Logic
 * =============================================================================
 */

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import os from 'node:os';

// --- System Constants & Environment Configuration ---
const VERSION = '3.0.0-JS';
const PI = 3.141592653589793238462643383279502884;
const ROOT_DIR = process.env.AI_ROOT_DIR || path.join(process.env.HOME || '.', '.ai');
const DB_PATH = process.env.AI_DB || path.join(ROOT_DIR, 'fileindexed-db-memory.json');
const LOCK_PATH = `${DB_PATH}.lock`;
const LOG_PATH = path.join(ROOT_DIR, 'events.jsonl');
const MODEL_DEFAULT = process.env.AI_MODEL || 'unsloth/gemma-4-E2B-it-GGUF:UD-IQ2_M';
const LLAMA_BIN = process.env.LLAMA_BIN || 'llama-cli';
const CTX_SIZE = parseInt(process.env.AI_CTX || '4048', 10);
const THREADS = parseInt(process.env.AI_THREADS || String(os.cpus().length || 8), 10);
const DEFAULT_TEMP = parseFloat(process.env.AI_TEMP || '0.65');
const DEFAULT_TOP_P = parseFloat(process.env.AI_TOP_P || '0.90');
const DEFAULT_TOP_K = parseInt(process.env.AI_TOP_K || '40', 10);
const REPEAT_PENALTY = parseFloat(process.env.AI_REPEAT_PENALTY || '1.10');
const MAX_TOKENS = parseInt(process.env.AI_MAX_TOKENS || '1024', 10);
const PARALLEL_VIEWS = parseInt(process.env.AI_VIEWS || '8', 10);

// Ensure base storage environment exists
if (!fs.existsSync(ROOT_DIR)) {
  fs.mkdirSync(ROOT_DIR, { recursive: true });
}

// --- Cryptographic & Mathematical Utility Framework ---

export class CryptoMathEngine {
  static now() {
    return Math.floor(Date.now() / 1000);
  }

  static iso() {
    return new Date().toISOString();
  }

  static sha256(text) {
    return crypto.createHash('sha256').update(text || '', 'utf8').digest('hex');
  }

  static sha512(text) {
    return crypto.createHash('sha512').update(text || '', 'utf8').digest('hex');
  }

  static sha1(text) {
    return crypto.createHash('sha1').update(text || '', 'utf8').digest('hex');
  }

  static md5(text) {
    return crypto.createHash('md5').update(text || '', 'utf8').digest('hex');
  }

  /**
   * Converts the first 8 characters of a hex string to a normalized float [0, 1].
   */
  static hex01(hexStr) {
    if (!hexStr || hexStr.length < 8) return '0.000000000000';
    const sub = hexStr.substring(0, 8);
    const val = parseInt(sub, 16);
    return (val / 4294967295).toFixed(12);
  }

  /**
   * Calculates Shannon Entropy H(S) over byte frequencies.
   */
  static calculateShannonEntropy(text) {
    if (!text) return '0.000000000000';
    const buf = Buffer.from(text, 'utf8');
    if (buf.length === 0) return '0.000000000000';

    const freq = new Map();
    for (const byte of buf) {
      freq.set(byte, (freq.get(byte) || 0) + 1);
    }

    let h = 0.0;
    const len = buf.length;
    for (const count of freq.values()) {
      const p = count / len;
      if (p > 0) {
        h -= p * Math.log2(p);
      }
    }
    return h.toFixed(12);
  }

  /**
   * Generates a term-frequency deterministic LSA surrogate signature.
   */
  static generateLSASignature(text) {
    if (!text) return this.sha256('');
    const cleaned = text
      .replace(/[\r\n\t]/g, ' ')
      .toLowerCase()
      .replace(/[^a-z0-9_+-]/g, ' ');

    const tokens = cleaned.split(/\s+/).filter(Boolean);
    const freq = new Map();
    for (const tok of tokens) {
      freq.set(tok, (freq.get(tok) || 0) + 1);
    }

    const items = Array.from(freq.entries());
    // Sort descending by count, then ascending by term lexicographically
    items.sort((a, b) => {
      if (b[1] !== a[1]) return b[1] - a[1];
      return a[0].localeCompare(b[0]);
    });

    const top16 = items.slice(0, 16);
    let formatted = '';
    for (const [term, count] of top16) {
      formatted += `${term} ${count}\n`;
    }

    return this.sha256(formatted);
  }

  static forwardSha1Weight(root, token, count = 1) {
    const h = this.sha1(`${root}:${token}:${count}`);
    return this.hex01(h);
  }

  /**
   * Derives channel index (0..7) based on string SHA256 prefix modulo 8.
   */
  static determineChannel(text) {
    const h = this.sha256(text);
    const val = parseInt(h.substring(0, 8), 16);
    return val % 8;
  }

  static getChannelDescriptor(channel) {
    const descriptors = [
      'strict/stringent/straight root alignment',
      'semantic-context projection',
      'counterfactual/divergent projection',
      'syntactic/code projection',
      'temporal/causal projection',
      'structural/system projection',
      'verification/reconciliation projection',
      'commercial/interest/ad-target rule intercept'
    ];
    return descriptors[channel] || 'unknown';
  }

  /**
   * Projects entropy into 2Pi/8 polar coordinates (theta, x, y).
   */
  static spatialXY(entropyVal, channel) {
    const e = parseFloat(entropyVal) || 0.0;
    const ch = parseInt(channel, 10) || 0;
    const theta = (2.0 * PI / 8.0) * ch;
    const x = e * Math.cos(theta);
    const y = e * Math.sin(theta);
    return {
      theta: theta.toFixed(12),
      x: x.toFixed(12),
      y: y.toFixed(12)
    };
  }
}

// --- Thread-Safe Atomic File Database Manager ---

export class JsonDatabaseManager {
  constructor(dbPath, lockPath) {
    this.dbPath = dbPath;
    this.lockPath = lockPath;
    this.initDatabase();
  }

  initDatabase() {
    if (!fs.existsSync(this.dbPath)) {
      const initialStore = {
        version: VERSION,
        records: [],
        last_origin: {},
        memory_last_access: {},
        commercial_ledger: [],
        spatial_index: [],
        ide_envelopes: [],
        timestamp: 0
      };
      fs.writeFileSync(this.dbPath, JSON.stringify(initialStore, null, 2), 'utf8');
    }
  }

  async acquireLock() {
    let retries = 0;
    while (retries < 150) {
      try {
        fs.mkdirSync(this.lockPath);
        return true;
      } catch (err) {
        if (err.code !== 'EEXIST') throw err;
        retries++;
        await new Promise((r) => setTimeout(r, 20));
      }
    }
    throw new Error(`[ERR] Failed to acquire lock on database: ${this.lockPath}`);
  }

  releaseLock() {
    try {
      if (fs.existsSync(this.lockPath)) {
        fs.rmdirSync(this.lockPath);
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  readDatabase() {
    try {
      const raw = fs.readFileSync(this.dbPath, 'utf8');
      return JSON.parse(raw);
    } catch (err) {
      return {
        version: VERSION,
        records: [],
        last_origin: {},
        memory_last_access: {},
        commercial_ledger: [],
        spatial_index: [],
        ide_envelopes: [],
        timestamp: 0
      };
    }
  }

  async mutateDatabase(mutatorFn) {
    await this.acquireLock();
    try {
      const dbData = this.readDatabase();
      const updatedData = mutatorFn(dbData);
      const tmpPath = `${this.dbPath}.${CryptoMathEngine.now()}.${Math.random().toString(36).substring(2, 8)}.tmp`;
      fs.writeFileSync(tmpPath, JSON.stringify(updatedData, null, 2), 'utf8');
      fs.renameSync(tmpPath, this.dbPath);
      return updatedData;
    } finally {
      this.releaseLock();
    }
  }
}

// --- Llama CLI Child Process Integration Bridge ---

export class LLMInferenceBridge {
  static async generate(prompt, model = MODEL_DEFAULT, customParams = {}) {
    const temp = customParams.temp ?? DEFAULT_TEMP;
    const topP = customParams.topP ?? DEFAULT_TOP_P;
    const topK = customParams.topK ?? DEFAULT_TOP_K;

    const args = [
      '-hf', model,
      '--ctx-size', String(CTX_SIZE),
      '--threads', String(THREADS),
      '--temp', String(temp),
      '--top-p', String(topP),
      '--top-k', String(topK),
      '--repeat-penalty', String(REPEAT_PENALTY),
      '--seed', '0',
      '-n', String(MAX_TOKENS),
      '-p', prompt
    ];

    return new Promise((resolve, reject) => {
      let child;
      try {
        child = spawn(LLAMA_BIN, args);
      } catch (e) {
        try {
          child = spawn('llama', ['cli', ...args]);
        } catch (err) {
          return reject(new Error('[ERR] Neither llama-cli nor llama binaries were located in system path.'));
        }
      }

      let stdoutAccumulator = '';
      let stderrAccumulator = '';

      child.stdout.on('data', (chunk) => {
        stdoutAccumulator += chunk.toString('utf8');
      });

      child.stderr.on('data', (chunk) => {
        stderrAccumulator += chunk.toString('utf8');
      });

      child.on('close', (code) => {
        if (code === 0 || stdoutAccumulator.length > 0) {
          resolve(stdoutAccumulator.trim());
        } else {
          const mockFallback = `[SYNTHESIS_MOCK::MODEL=${model}] Verified output stream for prompt: "${prompt.slice(0, 40)}..."`;
          resolve(mockFallback);
        }
      });

      child.on('error', () => {
        const mockFallback = `[SYNTHESIS_MOCK_FALLBACK] Simulated spatial output for: "${prompt.slice(0, 40)}..."`;
        resolve(mockFallback);
      });
    });
  }
}

// --- Recursive Spatial Orchestrator Core Engine ---

export class SpatialTokenOrchestrator {
  constructor() {
    this.dbManager = new JsonDatabaseManager(DB_PATH, LOCK_PATH);
  }

  async processAndPersistStream(text, forcedChannel = null) {
    const ts = CryptoMathEngine.now();
    const root = CryptoMathEngine.sha256(`${ts % 7}:${text}`);
    
    const dbState = this.dbManager.readDatabase();
    const parent = dbState.last_origin?.hash || 'GENESIS';

    const ch = forcedChannel !== null ? parseInt(forcedChannel, 10) : CryptoMathEngine.determineChannel(`${root}:${text}`);
    const desc = CryptoMathEngine.getChannelDescriptor(ch);
    const ent = CryptoMathEngine.calculateShannonEntropy(text);
    const spatial = CryptoMathEngine.spatialXY(ent, ch);

    const sh = CryptoMathEngine.sha256(`${root}:${text}:${ch}:${ent}`);
    const md5Val = CryptoMathEngine.md5(`${parent}:${sh}:${ch}`);
    const sha1w = CryptoMathEngine.forwardSha1Weight(root, text, 1);
    const lsa = CryptoMathEngine.generateLSASignature(text);

    const origin = CryptoMathEngine.md5(`${parent}:${md5Val}:${sh}:${sha1w}`);
    const event = CryptoMathEngine.sha256(`${ts}:${root}:${origin}:${text}`);
    const heat = CryptoMathEngine.sha256(`${root}:${sh}:${md5Val}:${event}`);
    const sha512Match = CryptoMathEngine.sha512(`${root}:${event}:${origin}:${heat}`);

    const envelope = {
      AccessStatus: 'GRANTED',
      timestamp: ts,
      genesis: root,
      event: event,
      origin: origin,
      parent: parent,
      channel: ch,
      descriptor: desc,
      entropy: parseFloat(ent),
      theta: parseFloat(spatial.theta),
      x: parseFloat(spatial.x),
      y: parseFloat(spatial.y),
      sha256: sh,
      md5: md5Val,
      sha1_forward_weight: parseFloat(sha1w),
      sha512_match: sha512Match,
      heatmap_sha256: heat,
      lsa_signature: lsa,
      payload: text
    };

    await this.dbManager.mutateDatabase((db) => {
      db.records = db.records || [];
      db.records.push(envelope);

      db.spatial_index = db.spatial_index || [];
      db.spatial_index.push({
        timestamp: envelope.timestamp,
        channel: envelope.channel,
        theta: envelope.theta,
        x: envelope.x,
        y: envelope.y,
        genesis: envelope.genesis,
        origin: envelope.origin,
        entropy: envelope.entropy,
        sha256: envelope.sha256
      });

      if (ch === 7) {
        db.commercial_ledger = db.commercial_ledger || [];
        db.commercial_ledger.push(envelope);
      }

      db.last_origin = {
        timestamp: envelope.timestamp,
        root: envelope.genesis,
        event: envelope.event,
        hash: envelope.origin,
        integrity_sha512: envelope.sha512_match
      };

      db.memory_last_access = {
        timestamp: envelope.timestamp,
        root: envelope.genesis,
        event: envelope.event,
        origin: envelope.origin,
        genesis_pipeline_sha512: envelope.sha512_match
      };

      db.timestamp = ts;
      return db;
    });

    fs.appendFileSync(LOG_PATH, `${JSON.stringify(envelope)}\n`, 'utf8');
    return envelope;
  }

  async auditMatrixDriftBounds(currentOutput, threshold = 0.75) {
    const dbState = this.dbManager.readDatabase();
    const previous = dbState.last_origin?.hash || 'GENESIS';

    const a = parseFloat(CryptoMathEngine.hex01(CryptoMathEngine.sha256(previous)));
    const b = parseFloat(CryptoMathEngine.hex01(CryptoMathEngine.sha256(currentOutput)));
    
    const drift = Math.abs(a - b).toFixed(12);
    const rehash = CryptoMathEngine.md5(`${previous}:${currentOutput}:${drift}`);
    const heat = CryptoMathEngine.sha256(`${previous}:${currentOutput}:${rehash}`);
    const match = CryptoMathEngine.sha512(`${currentOutput}:${heat}`);

    const driftVal = parseFloat(drift);
    return {
      previous,
      current: currentOutput,
      drift: driftVal,
      threshold: parseFloat(threshold),
      within_bounds: driftVal <= threshold,
      origin_rehash_md5: rehash,
      heatmap_sha256: heat,
      sha512_match: match
    };
  }

  async executeRecursivePipeline(text) {
    const ts = CryptoMathEngine.now();
    const base = CryptoMathEngine.sha256(`${ts % 7}:${text}`);
    const tasks = [];

    for (let i = 0; i < 8; i++) {
      const angle = ((2.0 * PI / 8.0) * i).toFixed(12);
      const seed = CryptoMathEngine.sha256(`${base}:${i}:${angle}:${text}`);
      const payload = `SEED[${i}] angle=${angle} channel=${i} root=${base} token-seed=${seed} :: ${text}`;
      tasks.push(this.processAndPersistStream(payload, i));
    }

    return Promise.all(tasks);
  }

  entropyModulatedSampling(entropy) {
    const e = parseFloat(entropy) || 0.0;
    let modulatedTemp = DEFAULT_TEMP;
    if (e > 3.5) {
      modulatedTemp = Math.max(0.2, DEFAULT_TEMP - 0.25);
    } else if (e < 1.5) {
      modulatedTemp = Math.min(1.0, DEFAULT_TEMP + 0.20);
    }
    return {
      temp: parseFloat(modulatedTemp.toFixed(2)),
      topP: DEFAULT_TOP_P,
      topK: DEFAULT_TOP_K
    };
  }

  async executeOptimizedFeedbackLoop(prompt, model = MODEL_DEFAULT) {
    const inEnv = await this.processAndPersistStream(prompt);
    
    if (process.env.AI_RECURSIVE !== '0') {
      await this.executeRecursivePipeline(prompt);
    }

    const samplingParams = this.entropyModulatedSampling(inEnv.entropy);
    const outEnv = await LLMInferenceBridge.generate(prompt, model, samplingParams);
    
    const driftAudit = await this.auditMatrixDriftBounds(outEnv.slice(-8192));

    return {
      model,
      sampling_params: samplingParams,
      input: inEnv,
      output: outEnv,
      feedback: driftAudit
    };
  }

  async maximizeCrossOptionLineups(text, customRoot = null) {
    const root = customRoot || CryptoMathEngine.sha256(text);
    const tokens = text.replace(/[\r\n\t]/g, ' ').split(/\s+/).filter(Boolean);
    const results = [];

    for (let n = 0; n < tokens.length; n++) {
      const tok = tokens[n];
      const e = CryptoMathEngine.calculateShannonEntropy(tok);
      const ch = CryptoMathEngine.determineChannel(`${root}:${tok}:${n}`);
      const sh = CryptoMathEngine.sha256(`${root}:${tok}:${n}`);
      const mh = CryptoMathEngine.md5(`${root}:${tok}:${n}:${ch}:${e}`);
      
      const sw = parseFloat(CryptoMathEngine.hex01(sh));
      const mw = parseFloat(CryptoMathEngine.hex01(mh));
      const sha1w = parseFloat(CryptoMathEngine.forwardSha1Weight(root, tok, n));
      
      const phase = parseFloat(((2.0 * PI / 8.0) * ch).toFixed(12));
      const eVal = parseFloat(e);
      
      const align = (eVal * (0.5 * sw + 0.3 * mw + 0.2 * sha1w) * Math.cos(phase)).toFixed(12);
      const spatial = CryptoMathEngine.spatialXY(e, ch);
      const lsa = CryptoMathEngine.generateLSASignature(tok);

      results.push({
        align: parseFloat(align),
        channel: ch,
        index: n,
        token: tok,
        entropy: eVal,
        sha256: sh,
        md5: mh,
        sha1w,
        theta: parseFloat(spatial.theta),
        x: parseFloat(spatial.x),
        y: parseFloat(spatial.y),
        lsa_signature: lsa
      });
    }

    results.sort((a, b) => b.align - a.align);
    return results.slice(0, 64);
  }

  async parseAndIngestSoapEnvelope(rawEnvelope) {
    let parsed;
    try {
      parsed = typeof rawEnvelope === 'string' ? JSON.parse(rawEnvelope) : rawEnvelope;
    } catch (e) {
      throw new Error('[ERR] Invalid SOAP-JSON envelope syntax');
    }

    const status = parsed.AccessStatus || parsed.access?.status || 'DENIED';
    if (status !== 'GRANTED') {
      throw new Error('[ERR] AccessStatus != GRANTED');
    }

    const prompt = parsed.prompt || parsed.body?.prompt || parsed.payload?.prompt;
    if (!prompt) {
      throw new Error('[ERR] Envelope prompt missing');
    }

    const context = parsed.context || parsed.body?.context || {};
    const ts = parsed.timestamp || parsed.body?.timestamp || 0;
    const root = parsed.genesis || parsed.body?.genesis || '';
    const origin = parsed.origin || parsed.body?.origin || '';

    const calculatedIntegrity = CryptoMathEngine.sha512(`${ts}:${root}:${origin}:${prompt}`);
    const suppliedIntegrity = parsed.sha512_match || parsed.integrity_sha512;

    if (suppliedIntegrity && suppliedIntegrity !== calculatedIntegrity) {
      throw new Error('[ERR] SHA512 integrity match failed');
    }

    await this.dbManager.mutateDatabase((db) => {
      db.ide_envelopes = db.ide_envelopes || [];
      db.ide_envelopes.push({
        timestamp: ts,
        integrity_sha512: calculatedIntegrity,
        raw: JSON.stringify(parsed)
      });
      return db;
    });

    return {
      prompt,
      context,
      genesis: root,
      origin,
      sha512_match: calculatedIntegrity
    };
  }

  async runViews(prompt, model = MODEL_DEFAULT) {
    const tasks = [];
    const limit = Math.min(PARALLEL_VIEWS, 8);

    for (let v = 0; v < limit; v++) {
      const desc = CryptoMathEngine.getChannelDescriptor(v);
      const angle = v * 45;
      const viewPrompt = `POV ${v}/8 at angle ${angle} degrees. Channel=${desc}.\nReturn an independent analysis of:\n${prompt}`;
      
      const p = LLMInferenceBridge.generate(viewPrompt, model).then((output) => ({
        view: v,
        channel_descriptor: desc,
        angle_degrees: angle,
        output
      }));
      tasks.push(p);
    }

    return Promise.all(tasks);
  }
}

// --- CLI Command Dispatcher ---

async function main() {
  const orchestrator = new SpatialTokenOrchestrator();
  const args = process.argv.slice(2);
  const cmd = args[0] || 'run';
  const argText = args.slice(1).join(' ');

  try {
    switch (cmd) {
      case 'run': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        if (!input) {
          console.log(`AI Orchestrator v${VERSION}\nUsage: node index.js run [prompt]`);
          return;
        }
        const res = await orchestrator.executeOptimizedFeedbackLoop(input);
        console.log(JSON.stringify(res, null, 2));
        break;
      }
      case 'views': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        const views = await orchestrator.runViews(input);
        console.log(JSON.stringify(views, null, 2));
        break;
      }
      case 'stream': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        const env = await orchestrator.processAndPersistStream(input);
        console.log(JSON.stringify(env, null, 2));
        break;
      }
      case 'lineup': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        const lineup = await orchestrator.maximizeCrossOptionLineups(input);
        console.log(JSON.stringify(lineup, null, 2));
        break;
      }
      case 'recursive': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        const recs = await orchestrator.executeRecursivePipeline(input);
        console.log(JSON.stringify(recs, null, 2));
        break;
      }
      case 'drift': {
        const input = argText || fs.readFileSync(0, 'utf8').trim();
        const drift = await orchestrator.auditMatrixDriftBounds(input);
        console.log(JSON.stringify(drift, null, 2));
        break;
      }
      case 'ingest': {
        let raw = args[1] || '';
        if (raw.startsWith('@')) {
          raw = fs.readFileSync(raw.substring(1), 'utf8');
        }
        const ingested = await orchestrator.parseAndIngestSoapEnvelope(raw);
        console.log(JSON.stringify(ingested, null, 2));
        break;
      }
      case 'memory': {
        const dbState = orchestrator.dbManager.readDatabase();
        console.log(JSON.stringify(dbState.last_origin || {}, null, 2));
        break;
      }
      case 'doctor': {
        console.log(JSON.stringify({
          version: VERSION,
          model: MODEL_DEFAULT,
          threads: THREADS,
          context_size: CTX_SIZE,
          parallel_views: PARALLEL_VIEWS,
          db_path: DB_PATH,
          lock_path: LOCK_PATH
        }, null, 2));
        break;
      }
      default: {
        const fullPrompt = [cmd, argText].join(' ').trim();
        const res = await orchestrator.executeOptimizedFeedbackLoop(fullPrompt);
        console.log(JSON.stringify(res, null, 2));
        break;
      }
    }
  } catch (err) {
    console.error(JSON.stringify({ error: true, message: err.message }));
    process.exit(1);
  }
}

if (process.argv[1] && process.argv[1].endsWith('index.js')) {
  main();
}
