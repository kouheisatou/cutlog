# cutlog — セルフホスト用イメージ（ffmpeg 同梱）
FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ffmpeg ca-certificates tini fonts-noto-cjk fontconfig \
 && rm -rf /var/lib/apt/lists/* \
 && test -f /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev

COPY src ./src
COPY web ./web
COPY scripts ./scripts

RUN mkdir -p /data && chown -R node:node /data /app
USER node

# まとめ動画に焼き込む文字のフォント。日本語のメモや表紙が豆腐にならないようにする
ENV RENDER_FONT_FILE=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
ENV DATA_DIR=/data PORT=8787
EXPOSE 8787
VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/api/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "src/index.js"]
