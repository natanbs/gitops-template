FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY server.js .
EXPOSE ${CONTAINER_PORT}
CMD ["node", "server.js"]