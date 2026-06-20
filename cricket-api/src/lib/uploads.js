import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ============================================================================
// Dependency-free image uploads.
// ----------------------------------------------------------------------------
// Admin uploads come in as a base64 data URL (JSON body), are decoded and
// written to `cricket-api/assets/images/uploads/`, and are served back over a
// public GET /uploads/:file route (no API key, like /health) so the Flutter
// app's Image.network can load them.
// ============================================================================

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// src/lib -> ../../assets/images/uploads
export const UPLOAD_DIR = path.resolve(__dirname, '..', '..', 'assets', 'images', 'uploads');

const MAX_BYTES = 6 * 1024 * 1024; // 6MB decoded ceiling

const EXT_BY_MIME = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

const MIME_BY_EXT = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  webp: 'image/webp',
  gif: 'image/gif',
};

function ensureDir() {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
}

/**
 * Decode + persist a base64 image.
 * @param {string} dataUrl  data URL ("data:image/png;base64,....") or raw base64.
 * @param {string} [mimeHint] used when `dataUrl` is raw base64.
 * @returns {{ filename: string, relativeUrl: string, bytes: number }}
 * @throws {Error} with .statusCode for invalid type / oversize.
 */
export function saveBase64Image(dataUrl, mimeHint = '') {
  if (!dataUrl || typeof dataUrl !== 'string') {
    const e = new Error('No image data provided');
    e.statusCode = 400;
    throw e;
  }

  let mime = mimeHint;
  let base64 = dataUrl;
  const match = /^data:([^;]+);base64,(.*)$/s.exec(dataUrl);
  if (match) {
    mime = match[1];
    base64 = match[2];
  }
  mime = String(mime || '').toLowerCase();
  const ext = EXT_BY_MIME[mime];
  if (!ext) {
    const e = new Error('Unsupported image type. Use PNG, JPG, WEBP or GIF.');
    e.statusCode = 415;
    throw e;
  }

  let buffer;
  try {
    buffer = Buffer.from(base64, 'base64');
  } catch {
    const e = new Error('Invalid base64 image data');
    e.statusCode = 400;
    throw e;
  }
  if (!buffer.length) {
    const e = new Error('Empty image');
    e.statusCode = 400;
    throw e;
  }
  if (buffer.length > MAX_BYTES) {
    const e = new Error('Image too large (max 6MB)');
    e.statusCode = 413;
    throw e;
  }

  ensureDir();
  const filename = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_DIR, filename), buffer);
  return { filename, relativeUrl: `/uploads/${filename}`, bytes: buffer.length };
}

/**
 * Resolve a requested upload filename to an absolute on-disk path, guarding
 * against path traversal. Returns null if invalid or missing.
 */
export function resolveUploadFile(name) {
  if (!name || typeof name !== 'string') return null;
  // Only a bare filename is allowed — no slashes, no '..'.
  if (name.includes('/') || name.includes('\\') || name.includes('..')) return null;
  const full = path.join(UPLOAD_DIR, name);
  if (!full.startsWith(UPLOAD_DIR)) return null;
  if (!fs.existsSync(full) || !fs.statSync(full).isFile()) return null;
  const ext = path.extname(full).slice(1).toLowerCase();
  return { full, contentType: MIME_BY_EXT[ext] || 'application/octet-stream' };
}
