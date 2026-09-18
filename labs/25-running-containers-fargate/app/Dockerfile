FROM node:22-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY app.js ./

EXPOSE 3000

RUN addgroup -S nodejs && adduser -S nodeuser -G nodejs
RUN chown -R nodeuser:nodejs /app
USER nodeuser

CMD ["npm", "start"]
