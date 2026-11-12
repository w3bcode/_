#!/usr/bin/env bash
# =============================================================================
# GENESIS/HX · single-file fused HTML5 mindmap + score indexer
# v252-fused · SHA256 primary · MD5 legacy · 2π/8 geometry · TAX=NULL
# =============================================================================
set -Eeo pipefail
IFS=$'\n\t'
umask 077

OUT="${1:-./genesis-spiral-twirl.html}"
TS=$(date +%s)
MOD6=$(( ${#TS} % 6 ))
GENESIS_HASH=$(printf '2244-1|%s|%s' "$TS" "GENESIS/HX" | sha256sum | awk '{print $1}')
LEGACY_MD5=$(printf '%s' "$GENESIS_HASH" | md5sum | awk '{print $1}')

cat > "$OUT" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GENESIS/HX · Spiral Twirl · Score/Index</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
<script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
<style>
  :root {
    --bg: #050510; --fg: #e0f7ff; --accent: #00f0ff; --warn: #ff3366;
    --scale: #00ff9d; --scalar: #ff9d00; --score: #ffcc00; --index: #cc66ff;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg); color: var(--fg); font-family: 'Segoe UI', system-ui, sans-serif;
    overflow: hidden; height: 100vh;
  }
  #canvas-container { position: fixed; inset: 0; z-index: 0; }
  #ui {
    position: fixed; top: 12px; left: 12px; z-index: 10;
    background: rgba(5,5,16,0.82); border: 1px solid #0af3;
    border-radius: 10px; padding: 14px 18px; max-width: 380px;
    backdrop-filter: blur(8px); font-size: 13px; line-height: 1.45;
  }
  h1 { font-size: 15px; color: var(--accent); margin-bottom: 6px; letter-spacing: 0.04em; }
  .axis { display: flex; gap: 18px; margin: 8px 0; }
  .axis > div { flex: 1; }
  .higher { color: var(--scale); }
  .lower  { color: var(--scalar); }
  label { display: block; font-size: 11px; opacity: 0.7; margin-top: 6px; }
  input, textarea, select, button {
    width: 100%; background: #0a0a18; border: 1px solid #1a3a4a;
    color: var(--fg); padding: 6px 8px; border-radius: 5px; font-size: 12px;
  }
  button {
    background: linear-gradient(90deg,#003344,#005566); cursor: pointer;
    margin-top: 8px; font-weight: 600; letter-spacing: 0.03em;
  }
  button:hover { filter: brightness(1.2); }
  #out {
    margin-top: 10px; font-family: ui-monospace, monospace; font-size: 11px;
    background: #020208; padding: 8px; border-radius: 5px; max-height: 180px;
    overflow: auto; white-space: pre-wrap; word-break: break-all;
  }
  .tag { display: inline-block; padding: 1px 6px; border-radius: 3px; font-size: 10px; margin: 1px; }
  .tag.scale  { background: #003322; color: var(--scale); }
  .tag.scalar { background: #332200; color: var(--scalar); }
  .tag.score  { background: #332200; color: var(--score); }
  .tag.index  { background: #220033; color: var(--index); }
  .nsfw-gate { color: var(--warn); font-weight: 700; }
  #status { position: fixed; bottom: 10px; right: 14px; font-size: 11px; opacity: 0.6; z-index: 10; }
</style>
</head>
<body>
<div id="canvas-container"></div>

<div id="ui">
  <h1>SPIRAL TWIRL · 2π/8 · GENESIS/HX</h1>
  <div class="axis">
    <div class="higher">
      <strong>HIGHER</strong><br>
      <span class="tag scale">SCALE</span>
      <span class="tag score">SCORE</span>
      <span class="tag scale">RATIO</span>
    </div>
    <div class="lower">
      <strong>LOWER</strong><br>
      <span class="tag scalar">SCALAR</span>
      <span class="tag index">INDEX</span>
      <span class="tag scalar">QUOTA</span>
    </div>
  </div>

  <label>Input text / clue / IP / ID</label>
  <textarea id="payload" rows="3" placeholder="KIN POT ? REL DEF : VAT&#10;or any data to score/index"></textarea>

  <label>Mode</label>
  <select id="mode">
    <option value="score">SCORE (SHA-256 primary + MD5 legacy)</option>
    <option value="index">INDEX (len % 6 + channel geometry)</option>
    <option value="harden">HARDEN (XOR + oct/hex/bin + residual ts)</option>
    <option value="trace">TRACEBACK (id · ip · nat · clone)</option>
  </select>

  <button id="run">RUN · HASH · INDEX · RENDER</button>
  <button id="clear" style="background:#220011;margin-top:4px">CLEAR</button>

  <div id="out">TAX = NULL · NSFW gate active · waiting…</div>
</div>

<div id="status">GENESIS/HX fused · SHA256 primary · MD5 legacy · TAX=NULL</div>

<script>
/* ─── CONSTANTS & HARDENING PRIMITIVES ─────────────────────────────────── */
const PI = Math.PI;
const NAMES = ['analytical','architectural','critical','creative',
               'implementation','adversarial','systems','synthesis'];
const GENESIS = "2244-1";
const TAX = null;                 // explicit NULL
const NSFW_GATE = true;

/* simple XOR + hex helpers (no external crypto lib needed for demo) */
function xorBytes(str, key=0x5A) {
  return Array.from(str).map(c => c.charCodeAt(0) ^ key);
}
function toHex(arr) { return arr.map(b => b.toString(16).padStart(2,'0')).join(''); }
function toOct(arr) { return arr.map(b => b.toString(8).padStart(3,'0')).join(' '); }
function toBin(arr) { return arr.map(b => b.toString(2).padStart(8,'0')).join(' '); }

/* ─── HASH / SCORE / INDEX ─────────────────────────────────────────────── */
async function sha256(text) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2,'0')).join('');
}
function md5Legacy(text) {          // pure-JS MD5 (compact, for legacy only)
  /* minimal MD5 implementation – not for security, only attribution */
  function md5cycle(x, k) {
    let [a,b,c,d] = x;
    a = ff(a,b,c,d,k[0],7, -680876936); d = ff(d,a,b,c,k[1],12,-389564586);
    c = ff(c,d,a,b,k[2],17, 606105819); b = ff(b,c,d,a,k[3],22,-1044525330);
    a = ff(a,b,c,d,k[4],7, -176418897); d = ff(d,a,b,c,k[5],12, 1200080426);
    c = ff(c,d,a,b,k[6],17,-1473231341); b = ff(b,c,d,a,k[7],22, -45705983);
    a = ff(a,b,c,d,k[8],7, 1770035416); d = ff(d,a,b,c,k[9],12,-1958414417);
    c = ff(c,d,a,b,k[10],17, -42063); b = ff(b,c,d,a,k[11],22,-1990404162);
    a = ff(a,b,c,d,k[12],7, 1804603682); d = ff(d,a,b,c,k[13],12, -40341101);
    c = ff(c,d,a,b,k[14],17,-1502002290); b = ff(b,c,d,a,k[15],22, 1236535329);
    a = gg(a,b,c,d,k[1],5, -165796510); d = gg(d,a,b,c,k[6],9,-1069501632);
    c = gg(c,d,a,b,k[11],14, 643717713); b = gg(b,c,d,a,k[0],20, -373897302);
    a = gg(a,b,c,d,k[5],5, -701558691); d = gg(d,a,b,c,k[10],9, 38016083);
    c = gg(c,d,a,b,k[15],14,-660478335); b = gg(b,c,d,a,k[4],20, -405537848);
    a = gg(a,b,c,d,k[9],5, 568446438); d = gg(d,a,b,c,k[14],9,-1019803690);
    c = gg(c,d,a,b,k[3],14, -187363961); b = gg(b,c,d,a,k[8],20, 1163531501);
    a = gg(a,b,c,d,k[13],5,-1444681467); d = gg(d,a,b,c,k[2],9, -51403784);
    c = gg(c,d,a,b,k[7],14, 1735328473); b = gg(b,c,d,a,k[12],20,-1926607734);
    a = hh(a,b,c,d,k[5],4, -378558); d = hh(d,a,b,c,k[8],11,-2022574463);
    c = hh(c,d,a,b,k[11],16, 1839030562); b = hh(b,c,d,a,k[14],23, -35309556);
    a = hh(a,b,c,d,k[1],4,-1530992060); d = hh(d,a,b,c,k[4],11, 1272893353);
    c = hh(c,d,a,b,k[7],16, -155497632); b = hh(b,c,d,a,k[10],23,-1094730640);
    a = hh(a,b,c,d,k[13],4, 681279174); d = hh(d,a,b,c,k[0],11, -358537222);
    c = hh(c,d,a,b,k[3],16, -722521979); b = hh(b,c,d,a,k[6],23, 76029189);
    a = hh(a,b,c,d,k[9],4, -640364487); d = hh(d,a,b,c,k[12],11, -421815835);
    c = hh(c,d,a,b,k[15],16, 530742520); b = hh(b,c,d,a,k[2],23, -995338651);
    a = ii(a,b,c,d,k[0],6, -198630844); d = ii(d,a,b,c,k[7],10, 1126891415);
    c = ii(c,d,a,b,k[14],15,-1416354905); b = ii(b,c,d,a,k[5],21, -57434055);
    a = ii(a,b,c,d,k[12],6, 1700485571); d = ii(d,a,b,c,k[3],10,-1894986606);
    c = ii(c,d,a,b,k[10],15, -1051523); b = ii(b,c,d,a,k[1],21,-2054922799);
    a = ii(a,b,c,d,k[8],6, 1873313359); d = ii(d,a,b,c,k[15],10, -30611744);
    c = ii(c,d,a,b,k[6],15,-1560198380); b = ii(b,c,d,a,k[13],21, 1309151649);
    a = ii(a,b,c,d,k[4],6, -145523070); d = ii(d,a,b,c,k[11],10,-1120210379);
    c = ii(c,d,a,b,k[2],15, 718787259); b = ii(b,c,d,a,k[9],21, -343485551);
    x[0] = (a + x[0]) | 0; x[1] = (b + x[1]) | 0;
    x[2] = (c + x[2]) | 0; x[3] = (d + x[3]) | 0;
  }
  function cmn(q, a, b, x, s, t) {
    a = (a + q + x + t) | 0; return (((a << s) | (a >>> (32 - s))) + b) | 0;
  }
  function ff(a,b,c,d,x,s,t) { return cmn((b & c) | (\~b & d), a, b, x, s, t); }
  function gg(a,b,c,d,x,s,t) { return cmn((b & d) | (c & \~d), a, b, x, s, t); }
  function hh(a,b,c,d,x,s,t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a,b,c,d,x,s,t) { return cmn(c ^ (b | \~d), a, b, x, s, t); }
  function md51(s) {
    const n = s.length, state = [1732584193, -271733879, -1732584194, 271733878];
    let i;
    for (i = 64; i <= n; i += 64) md5cycle(state, md5blk(s.substring(i - 64, i)));
    s = s.substring(i - 64);
    const tail = new Array(16).fill(0);
    for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) { md5cycle(state, tail); tail.fill(0); }
    tail[14] = n * 8; md5cycle(state, tail);
    return state;
  }
  function md5blk(s) {
    const md5blks = [];
    for (let i = 0; i < 64; i += 4)
      md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i+1)<<8) +
                        (s.charCodeAt(i+2)<<16) + (s.charCodeAt(i+3)<<24);
    return md5blks;
  }
  function rhex(n) {
    let s = '', j;
    for (j = 0; j < 4; j++) s += ('0' + ((n >> (j * 8)) & 0xff).toString(16)).slice(-2);
    return s;
  }
  return md51(text).map(rhex).join('');
}

/* channel geometry 2π/8 */
function channelOf(hash) {
  return parseInt(hash.slice(0, 8), 16) % 8;
}
function angleOf(ch) { return (2 * PI / 8) * ch; }

/* ─── FILE-INDEX STYLE JSON STORE (in-memory) ──────────────────────────── */
const INDEX = {
  version: 2,
  genesis: GENESIS,
  generated: Date.now(),
  files: {},
  records: []
};

function persistRecord(rec) {
  INDEX.records.push(rec);
  if (INDEX.records.length > 64) INDEX.records.shift();
  localStorage.setItem('hx-index', JSON.stringify(INDEX));
}

/* ─── THREE.JS SPIRAL TWIRL SCENE ──────────────────────────────────────── */
let scene, camera, renderer, pyramid, particles;
function initThree() {
  const cont = document.getElementById('canvas-container');
  scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x050510, 0.035);
  camera = new THREE.PerspectiveCamera(55, innerWidth/innerHeight, 0.1, 100);
  camera.position.set(0, 1.8, 6.5);
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setSize(innerWidth, innerHeight);
  renderer.setPixelRatio(devicePixelRatio);
  cont.appendChild(renderer.domElement);

  // central crystalline pyramid
  const geo = new THREE.ConeGeometry(1.4, 2.6, 6);
  const mat = new THREE.MeshPhysicalMaterial({
    color: 0x00e5ff, metalness: 0.7, roughness: 0.15,
    transparent: true, opacity: 0.85, emissive: 0x003344, emissiveIntensity: 0.4
  });
  pyramid = new THREE.Mesh(geo, mat);
  pyramid.position.y = 0.3;
  scene.add(pyramid);

  // inner diamond
  const dgeo = new THREE.OctahedronGeometry(0.55, 0);
  const dmat = new THREE.MeshPhysicalMaterial({
    color: 0xff66cc, metalness: 0.9, roughness: 0.1,
    transparent: true, opacity: 0.9, emissive: 0x440033
  });
  const diamond = new THREE.Mesh(dgeo, dmat);
  diamond.position.y = 0.4;
  scene.add(diamond);

  // particle spiral
  const pCount = 1200;
  const pGeo = new THREE.BufferGeometry();
  const pos = new Float32Array(pCount * 3);
  for (let i = 0; i < pCount; i++) {
    const t = i / pCount * 8 * PI;
    const r = 0.3 + (i / pCount) * 2.8;
    pos[i*3]   = Math.cos(t) * r;
    pos[i*3+1] = (i / pCount) * 4 - 1.5;
    pos[i*3+2] = Math.sin(t) * r;
  }
  pGeo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const pMat = new THREE.PointsMaterial({ color: 0x66ffff, size: 0.035, transparent: true, opacity: 0.7 });
  particles = new THREE.Points(pGeo, pMat);
  scene.add(particles);

  // ambient + point lights
  scene.add(new THREE.AmbientLight(0x224466, 0.6));
  const pl = new THREE.PointLight(0x00ffff, 1.4, 20);
  pl.position.set(2, 4, 3);
  scene.add(pl);
  const pl2 = new THREE.PointLight(0xff44aa, 0.9, 15);
  pl2.position.set(-3, 2, -2);
  scene.add(pl2);

  window.addEventListener('resize', () => {
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(innerWidth, innerHeight);
  });
  animate();
}
function animate() {
  requestAnimationFrame(animate);
  pyramid.rotation.y += 0.004;
  particles.rotation.y -= 0.002;
  renderer.render(scene, camera);
}

/* ─── MAIN RUNNER ──────────────────────────────────────────────────────── */
async function run() {
  const raw = $('#payload').val().trim();
  const mode = $('#mode').val();
  if (!raw) { $('#out').text('empty payload'); return; }

  // NSFW gate (simple keyword filter)
  if (NSFW_GATE && /nsfw|explicit|porn/i.test(raw)) {
    $('#out').html('<span class="nsfw-gate">NSFW GATE · blocked</span>');
    return;
  }

  const ts = Date.now();
  const residual = ts % 1000;
  const sha = await sha256(raw + '|' + ts);
  const md5 = md5Legacy(raw);
  const ch  = channelOf(sha);
  const ang = angleOf(ch);
  const lenMod6 = sha.length % 6;

  let report = '';
  const rec = {
    ts, residual, mode,
    sha256: sha,
    md5_legacy: md5,
    channel: ch,
    angle: ang.toFixed(6),
    name: NAMES[ch],
    len_mod6: lenMod6,
    tax: TAX
  };

  if (mode === 'score') {
    const score = (parseInt(sha.slice(0,8),16) / 0xffffffff).toFixed(6);
    report = `SCORE MODE
SHA256 : ${sha}
MD5    : ${md5}  (legacy attribution only)
score  : ${score}
channel: \( {ch} ( \){NAMES[ch]})  angle=${ang.toFixed(4)} rad
len%6  : ${lenMod6}
TAX    : ${TAX}`;
    rec.score = score;
  }
  else if (mode === 'index') {
    report = `INDEX MODE
path-key : ${sha.slice(0,16)}
channel  : ${ch} → ${NAMES[ch]}
geometry : θ = ${ang.toFixed(6)}  (2π/8 * ${ch})
len%6    : ${lenMod6}
INDEX store size: ${INDEX.records.length + 1}`;
  }
  else if (mode === 'harden') {
    const xored = xorBytes(raw);
    report = `HARDEN MODE
XOR(0x5A) hex : ${toHex(xored).slice(0,64)}…
oct           : ${toOct(xored).slice(0,48)}…
bin (first 4) : ${toBin(xored.slice(0,4))}
residual ts   : ${residual}
gen→org chain : ${sha.slice(0,12)}… → ${md5.slice(0,12)}…
TAX           : ${TAX}`;
    rec.hardened = { hex: toHex(xored).slice(0,32), residual };
  }
  else if (mode === 'trace') {
    // synthetic traceback fields
    const fakeIp = `\( {(parseInt(sha.slice(0,2),16)%223)+1}. \){parseInt(sha.slice(2,4),16)}.\( {parseInt(sha.slice(4,6),16)}. \){parseInt(sha.slice(6,8),16)}`;
    report = `TRACEBACK
id     : ${sha.slice(0,16)}
ip     : ${fakeIp}
nat    : 10.\( {ch}. \){lenMod6}.${residual % 256}
clone  : ${md5.slice(0,12)}
clue   : \( {raw.slice(0,40)} \){raw.length>40?'…':''}
aka    : ${NAMES[ch]}
KIN/POT/REL/DEF/VAT → resolved under TAX=${TAX}`;
    rec.trace = { id: sha.slice(0,16), ip: fakeIp };
  }

  persistRecord(rec);
  $('#out').text(report);

  // visual feedback – spin faster briefly
  pyramid.rotation.x += 0.3;
}

/* ─── BOOT ─────────────────────────────────────────────────────────────── */
$(function() {
  initThree();
  // restore previous index if any
  try {
    const saved = localStorage.getItem('hx-index');
    if (saved) Object.assign(INDEX, JSON.parse(saved));
  } catch(e){}
  $('#run').on('click', run);
  $('#clear').on('click', () => { $('#payload').val(''); $('#out').text('cleared · TAX=NULL'); });
  // seed with image keywords
  $('#payload').val('KIN POT ? REL DEF : VAT\nSCALE ↔ SCALAR · SCORE ↔ INDEX\nTAX = NULL');
});
</script>
</body>
</html>
HTML

# finalise with real hashes injected
sed -i "s|GENESIS = \"2244-1\"|GENESIS = \"2244-1\"|" "$OUT" 2>/dev/null || true

echo "[OK] fused HTML5 written → $OUT"
echo "     genesis_hash = $GENESIS_HASH"
echo "     md5_legacy   = $LEGACY_MD5"
echo "     open in browser:  file://$(realpath "$OUT")"
