FROM node:18-alpine

WORKDIR /app

RUN apk add --no-cache docker-cli

COPY . .

RUN npm install

CMD ["npm", "start"]
