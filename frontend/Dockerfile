# Etapa build
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
RUN npm ci || npm i
COPY . .
RUN npm run build

# Etapa runtime
FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
# Nginx: servir SPA y proxy a backend
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]