/**
 * Ed25519 signature check (RFC 8032) in plain JavaScript, with SHA-512, so licences are checked the same way in Node
 * (Mac, Linux, Windows) and in the Android app's hidden WebView, which has no Node crypto. Only verification is here:
 * licences are signed by the licence server.
 */
'use strict';

// ---------------------------------------------------------------- SHA-512
const K512 = [
  '428a2f98d728ae22', '7137449123ef65cd', 'b5c0fbcfec4d3b2f', 'e9b5dba58189dbbc', '3956c25bf348b538', '59f111f1b605d019', '923f82a4af194f9b', 'ab1c5ed5da6d8118',
  'd807aa98a3030242', '12835b0145706fbe', '243185be4ee4b28c', '550c7dc3d5ffb4e2', '72be5d74f27b896f', '80deb1fe3b1696b1', '9bdc06a725c71235', 'c19bf174cf692694',
  'e49b69c19ef14ad2', 'efbe4786384f25e3', '0fc19dc68b8cd5b5', '240ca1cc77ac9c65', '2de92c6f592b0275', '4a7484aa6ea6e483', '5cb0a9dcbd41fbd4', '76f988da831153b5',
  '983e5152ee66dfab', 'a831c66d2db43210', 'b00327c898fb213f', 'bf597fc7beef0ee4', 'c6e00bf33da88fc2', 'd5a79147930aa725', '06ca6351e003826f', '142929670a0e6e70',
  '27b70a8546d22ffc', '2e1b21385c26c926', '4d2c6dfc5ac42aed', '53380d139d95b3df', '650a73548baf63de', '766a0abb3c77b2a8', '81c2c92e47edaee6', '92722c851482353b',
  'a2bfe8a14cf10364', 'a81a664bbc423001', 'c24b8b70d0f89791', 'c76c51a30654be30', 'd192e819d6ef5218', 'd69906245565a910', 'f40e35855771202a', '106aa07032bbd1b8',
  '19a4c116b8d2d0c8', '1e376c085141ab53', '2748774cdf8eeb99', '34b0bcb5e19b48a8', '391c0cb3c5c95a63', '4ed8aa4ae3418acb', '5b9cca4f7763e373', '682e6ff3d6b2b8a3',
  '748f82ee5defb2fc', '78a5636f43172f60', '84c87814a1f0ab72', '8cc702081a6439ec', '90befffa23631e28', 'a4506cebde82bde9', 'bef9a3f7b2c67915', 'c67178f2e372532b',
  'ca273eceea26619c', 'd186b8c721c0c207', 'eada7dd6cde0eb1e', 'f57d4f7fee6ed178', '06f067aa72176fba', '0a637dc5a2c898a6', '113f9804bef90dae', '1b710b35131c471b',
  '28db77f523047d84', '32caab7b40c72493', '3c9ebe0a15c9bebc', '431d67c49c100d4c', '4cc5d4becb3e42b6', '597f299cfc657e2a', '5fcb6fab3ad6faec', '6c44198c4a475817',
].map((h) => BigInt('0x' + h));
const M64 = (1n << 64n) - 1n;
const rotr = (x, n) => ((x >> n) | (x << (64n - n))) & M64;

function sha512(bytes) {
  const n = bytes.length, total = Math.ceil((n + 17) / 128) * 128;
  const m = new Uint8Array(total);
  m.set(bytes); m[n] = 0x80;
  let bits = BigInt(n) * 8n;
  for (let i = total - 1; i >= total - 16; i--) { m[i] = Number(bits & 255n); bits >>= 8n; }
  const H = ['6a09e667f3bcc908', 'bb67ae8584caa73b', '3c6ef372fe94f82b', 'a54ff53a5f1d36f1', '510e527fade682d1', '9b05688c2b3e6c1f', '1f83d9abfb41bd6b', '5be0cd19137e2179'].map((h) => BigInt('0x' + h));
  const W = new Array(80);
  for (let o = 0; o < total; o += 128) {
    for (let i = 0; i < 16; i++) {
      let w = 0n;
      for (let j = 0; j < 8; j++) w = (w << 8n) | BigInt(m[o + i * 8 + j]);
      W[i] = w;
    }
    for (let i = 16; i < 80; i++) {
      const s0 = rotr(W[i - 15], 1n) ^ rotr(W[i - 15], 8n) ^ (W[i - 15] >> 7n);
      const s1 = rotr(W[i - 2], 19n) ^ rotr(W[i - 2], 61n) ^ (W[i - 2] >> 6n);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) & M64;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 80; i++) {
      const S1 = rotr(e, 14n) ^ rotr(e, 18n) ^ rotr(e, 41n);
      const ch = (e & f) ^ (~e & M64 & g);
      const t1 = (h + S1 + ch + K512[i] + W[i]) & M64;
      const S0 = rotr(a, 28n) ^ rotr(a, 34n) ^ rotr(a, 39n);
      const mj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + mj) & M64;
      h = g; g = f; f = e; e = (d + t1) & M64; d = c; c = b; b = a; a = (t1 + t2) & M64;
    }
    H[0] = (H[0] + a) & M64; H[1] = (H[1] + b) & M64; H[2] = (H[2] + c) & M64; H[3] = (H[3] + d) & M64;
    H[4] = (H[4] + e) & M64; H[5] = (H[5] + f) & M64; H[6] = (H[6] + g) & M64; H[7] = (H[7] + h) & M64;
  }
  const out = new Uint8Array(64);
  H.forEach((v, i) => { for (let j = 7; j >= 0; j--) { out[i * 8 + j] = Number(v & 255n); v >>= 8n; } });
  return out;
}

// ---------------------------------------------------------------- curve
const P = (1n << 255n) - 19n;
const L = (1n << 252n) + 27742317777372353535851937790883648493n;
const mod = (a, m = P) => { const r = a % m; return r >= 0n ? r : r + m; };
function pow(b, e, m = P) { let r = 1n; b = mod(b, m); while (e > 0n) { if (e & 1n) r = (r * b) % m; b = (b * b) % m; e >>= 1n; } return r; }
const inv = (a) => pow(a, P - 2n);
const D = mod(-121665n * inv(121666n));
const I = pow(2n, (P - 1n) / 4n);
const Gy = mod(4n * inv(5n));

function recoverX(y, sign) {
  const y2 = (y * y) % P;
  const x2 = mod((y2 - 1n) * inv(D * y2 + 1n));
  if (x2 === 0n) return sign ? null : 0n;
  let x = pow(x2, (P + 3n) / 8n);
  if (mod(x * x - x2) !== 0n) x = (x * I) % P;
  if (mod(x * x - x2) !== 0n) return null;
  if ((x & 1n) !== BigInt(sign)) x = P - x;
  return x;
}
const Gx = recoverX(Gy, 0);
const G = [Gx, Gy, 1n, (Gx * Gy) % P];       // extended coordinates (X, Y, Z, T)
const ZERO = [0n, 1n, 1n, 0n];

function add(p, q) {
  const A = ((p[1] - p[0]) * (q[1] - q[0])) % P, B = ((p[1] + p[0]) * (q[1] + q[0])) % P;
  const C = (2n * p[3] * q[3] * D) % P, Dd = (2n * p[2] * q[2]) % P;
  const E = B - A, F = Dd - C, Gg = Dd + C, H = B + A;
  return [mod(E * F), mod(Gg * H), mod(F * Gg), mod(E * H)];
}
function mul(p, s) { let q = ZERO; while (s > 0n) { if (s & 1n) q = add(q, p); p = add(p, p); s >>= 1n; } return q; }
function equal(p, q) { return mod(p[0] * q[2] - q[0] * p[2]) === 0n && mod(p[1] * q[2] - q[1] * p[2]) === 0n; }

const le = (b) => { let n = 0n; for (let i = b.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(b[i]); return n; };
function decodePoint(b) {
  if (b.length !== 32) return null;
  const c = Uint8Array.from(b), sign = c[31] >> 7;
  c[31] &= 0x7f;
  const y = le(c);
  if (y >= P) return null;
  const x = recoverX(y, sign);
  return x === null ? null : [x, y, 1n, (x * y) % P];
}

/** true when `sig` (64 bytes) is `publicKey`'s (32 bytes) signature of `message` (bytes). */
function verify(sig, message, publicKey) {
  try {
    if (!sig || sig.length !== 64 || !publicKey || publicKey.length !== 32) return false;
    const A = decodePoint(publicKey), R = decodePoint(sig.subarray(0, 32));
    if (!A || !R) return false;
    const S = le(sig.subarray(32));
    if (S >= L) return false;
    const h = new Uint8Array(64 + message.length);
    h.set(sig.subarray(0, 32), 0); h.set(publicKey, 32); h.set(message, 64);
    const k = mod(le(sha512(h)), L);
    return equal(mul(G, S), add(R, mul(A, k)));
  } catch (_) { return false; }
}

module.exports = { verify, sha512 };
