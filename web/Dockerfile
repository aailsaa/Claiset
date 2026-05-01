FROM --platform=linux/amd64 node:20-alpine AS build
WORKDIR /app

COPY web/package.json web/package-lock.json ./
RUN npm ci

COPY web/ ./

# Strip dev-only API base URLs from any copied .env so they are not baked into the bundle.
RUN set -e; \
    for f in .env .env.local .env.production .env.production.local; do \
      if [ -f "$$f" ]; then \
        sed -i '/^VITE_ITEMS_API=/d;/^VITE_OUTFITS_API=/d;/^VITE_SCHEDULE_API=/d' "$$f" || true; \
      fi; \
    done

# Vite does not overwrite env vars already set.
ENV VITE_ITEMS_API="" \
    VITE_OUTFITS_API="" \
    VITE_SCHEDULE_API=""

RUN npm run build

FROM --platform=linux/amd64 nginx:1.27-alpine
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80

