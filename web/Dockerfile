FROM node:20-alpine AS build
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
    VITE_SCHEDULE_API="" \
    VITE_GOOGLE_CLIENT_ID="551920137993-5re842ov91rtdbtil3o6vi8lglmvpool.apps.googleusercontent.com"

RUN npm run build

FROM nginx:1.27-alpine
COPY web/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
COPY web/nginx.conf /opt/claiset-nginx-default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]

