import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { config } from '../config.js';

export const run = promisify(execFile);

export function id(prefix = '') {
  return prefix + crypto.randomBytes(9).toString('base64url');
}

export function inviteCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 紛らわしい文字を外す
  let out = '';
  for (let i = 0; i < 8; i += 1) out += alphabet[crypto.randomInt(alphabet.length)];
  return out;
}

export function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return `scrypt$${salt}$${crypto.scryptSync(password, salt, 64).toString('hex')}`;
}

export function verifyPassword(password, stored) {
  if (!stored) return false;
  const [scheme, salt, hash] = String(stored).split('$');
  if (scheme !== 'scrypt' || !salt || !hash) return false;
  const check = crypto.scryptSync(password, salt, 64).toString('hex');
  const a = Buffer.from(hash, 'hex');
  const b = Buffer.from(check, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export async function ffprobe(file) {
  try {
    const { stdout } = await run(config.ffmpeg.probe, [
      '-v', 'error', '-show_entries', 'format=duration:stream=width,height',
      '-of', 'json', file,
    ]);
    const j = JSON.parse(stdout);
    const stream = (j.streams || []).find((s) => s.width) || {};
    return {
      durationMs: j.format?.duration ? Math.round(Number(j.format.duration) * 1000) : null,
      width: stream.width || null,
      height: stream.height || null,
    };
  } catch {
    return { durationMs: null, width: null, height: null };
  }
}

export async function makeThumb(input, output) {
  try {
    await run(config.ffmpeg.bin, ['-y', '-i', input, '-frames:v', '1', '-vf', "scale='min(640,iw)':-2", output]);
    return true;
  } catch {
    return false;
  }
}

// アカウントの顔用に、真ん中を正方形で切り出して小さくする。
export async function makeSquare(input, output, size = 256) {
  try {
    await run(config.ffmpeg.bin, ['-y', '-i', input, '-frames:v', '1',
      '-vf', `scale=${size}:${size}:force_original_aspect_ratio=increase,crop=${size}:${size}`,
      '-q:v', '4', output]);
    return true;
  } catch {
    return false;
  }
}

// tzOffset は JavaScript の getTimezoneOffset()（UTCより遅れている分数。JSTなら -540）
export function localDateOf(takenAtIso, tzOffsetMinutes) {
  const t = new Date(takenAtIso).getTime() - tzOffsetMinutes * 60 * 1000;
  return new Date(t).toISOString().slice(0, 10);
}

export async function sha256File(file) {
  const { createReadStream } = await import('node:fs');
  return new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    createReadStream(file).on('data', (d) => h.update(d)).on('end', () => resolve(h.digest('hex'))).on('error', reject);
  });
}

export function asyncRoute(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}
