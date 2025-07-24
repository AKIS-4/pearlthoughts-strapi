# Stage 1: Build 
FROM node:20-alpine AS builder
WORKDIR /app
COPY . .
RUN npm install
RUN yarn build

# Stage 2: Deploy
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app ./
EXPOSE 1337
CMD ["sh", "-c", "until nc -z -v -w30 $DATABASE_HOST 5432; do echo 'Waiting for Postgres...'; sleep 5; done; yarn start"]

