// 保存先アダプタ。local（既定）と S3互換（MinIO・AWS S3・R2 など）を同じAPIで扱う。
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { config, paths } from '../config.js';

class LocalStorage {
  constructor(dir) {
    this.dir = dir;
    this.driver = 'local';
    fs.mkdirSync(dir, { recursive: true });
  }

  full(key) { return path.join(this.dir, path.basename(key)); }

  async put(key, srcFile) {
    await fsp.copyFile(srcFile, this.full(key));
    return key;
  }

  async putBuffer(key, buf) {
    await fsp.writeFile(this.full(key), buf);
    return key;
  }

  async getPath(key) {
    // 一時ファイルへ落とさずに済むので、ffmpeg からそのまま読める
    return this.full(key);
  }

  async exists(key) { return fs.existsSync(this.full(key)); }

  async delete(key) { await fsp.unlink(this.full(key)).catch(() => {}); }

  // range を渡すと、その範囲だけを読む（動画の頭出し・早送りに要る）
  async stream(key, range) {
    if (range) return fs.createReadStream(this.full(key), { start: range.start, end: range.end });
    return fs.createReadStream(this.full(key));
  }

  async size(key) {
    const st = await fsp.stat(this.full(key)).catch(() => null);
    return st ? st.size : 0;
  }
}

class S3Storage {
  constructor(opts) {
    this.opts = opts;
    this.driver = 's3';
    this.ready = (async () => {
      const { S3Client } = await import('@aws-sdk/client-s3');
      this.client = new S3Client({
        region: opts.region,
        endpoint: opts.endpoint || undefined,
        forcePathStyle: opts.forcePathStyle,
        credentials: opts.accessKeyId
          ? { accessKeyId: opts.accessKeyId, secretAccessKey: opts.secretAccessKey }
          : undefined,
      });
      const s3 = await import('@aws-sdk/client-s3');
      this.cmd = s3;
    })();
  }

  objKey(key) { return `${this.opts.prefix}/${path.basename(key)}`.replace(/^\/+/, ''); }

  async put(key, srcFile) {
    await this.ready;
    await this.client.send(new this.cmd.PutObjectCommand({
      Bucket: this.opts.bucket, Key: this.objKey(key), Body: fs.createReadStream(srcFile),
    }));
    return key;
  }

  async putBuffer(key, buf) {
    await this.ready;
    await this.client.send(new this.cmd.PutObjectCommand({
      Bucket: this.opts.bucket, Key: this.objKey(key), Body: buf,
    }));
    return key;
  }

  async stream(key, range) {
    await this.ready;
    const out = await this.client.send(new this.cmd.GetObjectCommand({
      Bucket: this.opts.bucket,
      Key: this.objKey(key),
      ...(range ? { Range: `bytes=${range.start}-${range.end}` } : {}),
    }));
    return out.Body;
  }

  // ffmpeg はローカルのファイルしか読めないので、一時ファイルへ落とす
  async getPath(key) {
    const tmp = path.join(paths.tmp, `s3_${path.basename(key)}`);
    if (!fs.existsSync(tmp)) {
      const body = await this.stream(key);
      await fsp.writeFile(tmp, body);
    }
    return tmp;
  }

  async exists(key) {
    await this.ready;
    try {
      await this.client.send(new this.cmd.HeadObjectCommand({ Bucket: this.opts.bucket, Key: this.objKey(key) }));
      return true;
    } catch { return false; }
  }

  async delete(key) {
    await this.ready;
    await this.client.send(new this.cmd.DeleteObjectCommand({ Bucket: this.opts.bucket, Key: this.objKey(key) }))
      .catch(() => {});
  }

  async size(key) {
    await this.ready;
    try {
      const h = await this.client.send(new this.cmd.HeadObjectCommand({ Bucket: this.opts.bucket, Key: this.objKey(key) }));
      return h.ContentLength || 0;
    } catch { return 0; }
  }
}

export const storage = config.storage.driver === 's3'
  ? new S3Storage(config.storage.s3)
  : new LocalStorage(paths.media);

export const renderStorage = new LocalStorage(paths.renders);
