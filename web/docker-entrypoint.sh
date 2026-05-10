#!/bin/sh
set -e
# Single web image for stable + canary; tier comes from Pod env (Terraform).
tier="${SPA_TIER:-unknown}"
sed "s|__SPA_TIER__|${tier}|g" /opt/claiset-nginx-default.conf.template >/etc/nginx/conf.d/default.conf
exec nginx -g "daemon off;"
