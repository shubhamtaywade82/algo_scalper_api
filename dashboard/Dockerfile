# syntax=docker/dockerfile:1

FROM node:20-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci --silent

COPY . .
# Vite bakes this into the bundle: it is the dashboard-tier token (not the operator token), so serve the dashboard
# only on a trusted interface. Empty is fine where Rails does not enforce API_DASHBOARD_TOKEN.
ARG VITE_API_DASHBOARD_TOKEN=""
ENV VITE_API_DASHBOARD_TOKEN=$VITE_API_DASHBOARD_TOKEN
RUN npm run build

FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80
