# Docker Hub images through Google's mirror: works from regions where Docker Hub is blocked.
FROM mirror.gcr.io/library/node:22-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV NODE_ENV=production DATA_DIR=/data PORT=3000
VOLUME /data
EXPOSE 3000
CMD ["node", "--disable-warning=ExperimentalWarning", "src/index.js"]
