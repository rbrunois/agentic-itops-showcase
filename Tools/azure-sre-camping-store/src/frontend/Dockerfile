FROM node:24-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

FROM node:24-alpine
WORKDIR /app

COPY --from=build /app/build ./build
COPY server ./server
RUN mkdir /app/data && chown node:node /app/data
USER node
ENV HOST=0.0.0.0
ENV PORT=8080
ENV DEMO_DATA_FILE=/app/data/presentation.json
EXPOSE 8080
CMD ["node", "server/index.mjs"]
