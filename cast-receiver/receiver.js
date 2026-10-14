// Recepteur Chromecast de Vinland (voir index.html pour le protocole).
'use strict';

const NAMESPACE = 'urn:x-cast:fr.vinland.cast';
const DEFAULT_ACCENT = '#1db954';

const $ = (id) => document.getElementById(id);
const media = $('media');
const context = cast.framework.CastReceiverContext.getInstance();
const player = context.getPlayerManager();

// --- Etat affiche -----------------------------------------------------

let accent = DEFAULT_ACCENT;
let lyrics = null; // { synced, lines: [{ t, text }] }
// Paroles et couleur par titre : elles peuvent arriver avant ou apres le
// chargement du titre lui-meme.
const extras = new Map();
let currentId = null;
let shownLine = -2;

function setAccent(color) {
  accent = /^#[0-9a-f]{6}$/i.test(color || '') ? color : DEFAULT_ACCENT;
  document.documentElement.style.setProperty('--accent', accent);
}

function showMedia(info) {
  const meta = (info && info.metadata) || {};
  currentId = info ? info.contentId : null;
  $('title').textContent = meta.title || '';
  $('artist').textContent = meta.artist || meta.albumArtist || '';
  $('album').textContent = meta.albumName || '';
  const image = meta.images && meta.images[0] && meta.images[0].url;
  $('cover').style.backgroundImage = image ? `url("${image}")` : '';
  applyExtras();
}

function applyExtras() {
  const data = extras.get(currentId) || {};
  setAccent(data.accent);
  showLyrics(data.lines ? data : null);
}

function showLyrics(data) {
  lyrics = data && data.lines && data.lines.length ? data : null;
  shownLine = -2;
  const box = $('lyrics');
  const lines = $('lines');
  lines.textContent = '';
  lines.style.transform = '';
  box.classList.toggle('none', !lyrics);
  if (!lyrics) return;
  lyrics.synced = lyrics.lines.every((l) => typeof l.t === 'number');
  box.classList.toggle('plain', !lyrics.synced);
  for (const l of lyrics.lines) {
    const div = document.createElement('div');
    div.textContent = l.text || ' ';
    lines.appendChild(div);
  }
}

function activeLine(ms) {
  if (!lyrics || !lyrics.synced) return -1;
  let found = -1;
  for (let i = 0; i < lyrics.lines.length; i++) {
    if (lyrics.lines[i].t <= ms) found = i; else break;
  }
  return found;
}

function updateLyrics(ms) {
  if (!lyrics) return;
  const lines = $('lines');
  if (!lyrics.synced) {
    // Paroles simples : defilement lent sur la duree du titre.
    const duration = media.duration || 0;
    if (duration > 0) {
      const max = Math.max(0, lines.scrollHeight - $('lyrics').clientHeight);
      lines.style.transform = `translateY(${-max * (ms / 1000 / duration)}px)`;
    }
    return;
  }
  const index = activeLine(ms);
  if (index === shownLine) return;
  const children = lines.children;
  if (children[shownLine]) children[shownLine].classList.remove('on');
  shownLine = index;
  const el = children[Math.max(0, index)];
  if (index >= 0 && el) el.classList.add('on');
  if (el) {
    const target = el.offsetTop - $('lyrics').clientHeight * 0.32;
    lines.style.transform = `translateY(${-Math.max(0, target)}px)`;
  }
}

const fmt = (s) => {
  if (!isFinite(s) || s < 0) s = 0;
  const m = Math.floor(s / 60);
  return `${m}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
};

// --- Analyse du son ---------------------------------------------------
//
// La Web Audio API ne peut lire le son que si le serveur autorise les
// requetes d'une autre origine (CORS). Une fois le lecteur branche sur
// l'analyse, un flux sans CORS serait muet : on verifie donc une fois sur
// le premier titre, et sans CORS on garde la pulsation au repos.

let analyser = null;
let corsChecked = false;
let bins = null;

async function corsAllowed(url) {
  const ctrl = new AbortController();
  try {
    const res = await fetch(url, { mode: 'cors', headers: { Range: 'bytes=0-1' }, signal: ctrl.signal });
    ctrl.abort();
    return res.ok;
  } catch (e) {
    return false;
  }
}

async function prepareAnalysis(url) {
  if (corsChecked) return;
  corsChecked = true;
  if (!(await corsAllowed(url))) return;
  try {
    media.crossOrigin = 'anonymous';
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const source = ctx.createMediaElementSource(media);
    analyser = ctx.createAnalyser();
    analyser.fftSize = 2048;
    analyser.smoothingTimeConstant = 0.55;
    source.connect(analyser);
    analyser.connect(ctx.destination);
    bins = new Uint8Array(analyser.frequencyBinCount);
    media.addEventListener('play', () => ctx.resume());
  } catch (e) {
    analyser = null;
  }
}

function readLevels() {
  if (!analyser) return null;
  analyser.getByteFrequencyData(bins);
  const hzPerBin = analyser.context.sampleRate / analyser.fftSize;
  let bass = 0, nb = 0, mid = 0, nm = 0;
  for (let i = 1; i < bins.length; i++) {
    const hz = i * hzPerBin;
    if (hz > 2000) break;
    if (hz >= 20 && hz <= 150) { bass += bins[i]; nb++; } else if (hz > 150) { mid += bins[i]; nm++; }
  }
  return { bass: nb ? bass / nb / 255 : 0, mid: nm ? mid / nm / 255 : 0 };
}

// Meme logique que lib/domain/beat_pulse.dart (BeatPulse + PulseRings).
const beat = {
  peak: 0.05, bassPeak: 0.05, avg: 0, level: 0, since: 10,
  add(bass, mid, dt) {
    this.since += dt;
    const raw = bass * 0.75 + mid * 0.25;
    const decay = Math.pow(0.84, dt);
    this.peak = Math.max(raw, this.peak * decay);
    this.bassPeak = Math.max(bass, this.bassPeak * decay);
    const norm = this.peak <= 0.02 ? 0 : Math.min(1, raw / this.peak);
    const k = norm > this.level ? 0.6 : 1 - Math.pow(0.02, dt);
    this.level += (norm - this.level) * Math.min(1, k);
    const b = this.bassPeak <= 0.02 ? 0 : bass / this.bassPeak;
    const hit = b >= 0.18 && b > this.avg * 1.35 && this.since >= 0.28;
    this.avg += (b - this.avg) * Math.min(1, 1 - Math.pow(0.0025, dt));
    if (!hit) return null;
    this.since = 0;
    return b;
  },
};

const rings = [];
const LIFETIME = 1.6;
function glowAt(d) {
  let g = 0;
  for (const r of rings) {
    const t = r.age / LIFETIME;
    const x = (d - t * 1.15) / 0.22;
    g += r.strength * (1 - t * t) * Math.exp(-x * x);
  }
  return Math.min(1, g);
}

// --- Dessin -----------------------------------------------------------

const canvas = $('hex');
const g = canvas.getContext('2d');
const R = 30; // rayon d'un hexagone, en pixels
let width = 0, height = 0, hexPath = null;

function resize() {
  width = canvas.width = window.innerWidth;
  height = canvas.height = window.innerHeight;
  hexPath = new Path2D();
  const inner = R * 0.88;
  for (let i = 0; i < 6; i++) {
    const a = Math.PI / 6 + (i * Math.PI) / 3;
    const x = inner * Math.cos(a), y = inner * Math.sin(a);
    i === 0 ? hexPath.moveTo(x, y) : hexPath.lineTo(x, y);
  }
  hexPath.closePath();
}
window.addEventListener('resize', resize);
resize();

function rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

let last = 0;
function frame(now) {
  const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
  last = now;
  const playing = !media.paused && !media.ended && currentId !== null;

  for (const r of rings) r.age += dt;
  while (rings.length && rings[0].age >= LIFETIME) rings.shift();

  const levels = playing ? readLevels() : null;
  let idle = 0;
  if (levels) {
    const hit = beat.add(levels.bass, levels.mid, dt);
    if (hit !== null) rings.push({ age: 0, strength: 0.35 + 0.65 * hit });
  } else {
    beat.add(0, 0, dt);
    if (playing) {
      // Sans analyse du son : lente respiration, pas de fausses vagues.
      idle = 0.12 + 0.08 * Math.sin(now / 1400);
    } else {
      idle = 0.12;
    }
  }
  if (rings.length > 6) rings.shift();
  const lvl = Math.max(beat.level, idle);

  // Les vagues partent de la pochette (ou du centre a l'accueil).
  const cover = $('cover').getBoundingClientRect();
  const cx = playing ? cover.left + cover.width / 2 : width / 2;
  const cy = playing ? cover.top + cover.height / 2 : height / 2;
  const maxDist = Math.hypot(Math.max(cx, width - cx), Math.max(cy, height - cy));
  const [r, gr, b] = rgb(accent);

  g.clearRect(0, 0, width, height);
  g.lineWidth = 2;
  const w = Math.sqrt(3) * R, h = 1.5 * R;
  for (let row = -1, y = 0; y < height + R; row++, y = row * h) {
    const shift = row % 2 ? w / 2 : 0;
    for (let col = -1; col * w < width + R; col++) {
      const x = col * w + shift;
      const d = Math.hypot(x - cx, y - cy) / maxDist;
      const v = Math.min(1, 0.08 + glowAt(d) * 0.85 + lvl * 0.3 * (1 - d));
      g.setTransform(1, 0, 0, 1, x, y);
      g.fillStyle = `rgba(${r},${gr},${b},${0.03 + v * 0.3})`;
      g.fill(hexPath);
      g.strokeStyle = `rgba(${r},${gr},${b},${0.1 + v * 0.85})`;
      g.stroke(hexPath);
    }
  }
  g.setTransform(1, 0, 0, 1, 0, 0);

  // La pochette bat legerement avec la musique.
  $('cover').style.setProperty('--kick', String(1 + glowAt(0) * 0.035));

  const t = media.currentTime || 0;
  const total = media.duration || 0;
  $('pos').textContent = fmt(t);
  $('dur').textContent = fmt(total);
  $('fill').style.width = total ? `${(100 * t) / total}%` : '0';
  updateLyrics(t * 1000);

  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// --- Cast -------------------------------------------------------------

player.setMediaElement(media);

player.setMessageInterceptor(cast.framework.messages.MessageType.LOAD, async (request) => {
  const info = request.media;
  if (info && info.contentId) await prepareAnalysis(info.contentId);
  return request;
});

player.addEventListener(cast.framework.events.EventType.PLAYER_LOAD_COMPLETE, () => {
  showMedia(player.getMediaInformation());
});
player.addEventListener(cast.framework.events.EventType.MEDIA_STATUS, () => {
  const state = player.getPlayerState();
  document.body.classList.toggle('playing', state !== cast.framework.messages.PlayerState.IDLE);
});

context.addCustomMessageListener(NAMESPACE, (event) => {
  const data = event.data || {};
  if (data.type !== 'EXTRAS' || !data.contentId) return;
  extras.set(data.contentId, data);
  // On ne garde que les derniers titres.
  while (extras.size > 5) extras.delete(extras.keys().next().value);
  if (data.contentId === currentId) applyExtras();
});

const options = new cast.framework.CastReceiverOptions();
options.customNamespaces = { [NAMESPACE]: cast.framework.system.MessageType.JSON };
// Pas de lecteur video (Shaka, HLS) a charger : on ne lit que du mp3.
options.skipPlayersLoad = true;
context.start(options);
