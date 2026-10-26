#!/usr/bin/env bash
set -euo pipefail
umask 077

release_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
deploy_root=${1:-"$HOME/ripple"}
mkdir -p "$deploy_root/backups"
deploy_root=$(cd -- "$deploy_root" && pwd)
exec 9>"$deploy_root/deploy.lock"
flock -n 9 || { echo "Another deployment is running" >&2; exit 1; }

if [[ ! -f "$deploy_root/.env" ]]; then
  {
    printf 'SITE_ADDRESS=ripple.jasperlab.dev\n'
    printf 'MYSQL_ROOT_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'MYSQL_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'AUTH_SECRET=%s\n' "$(openssl rand -hex 32)"
  } > "$deploy_root/.env"
fi
chmod 600 "$deploy_root/.env"

project_name=${RIPPLE_PROJECT:-ripple-prod}
compose=(docker compose --project-name "$project_name" --env-file "$deploy_root/.env" --env-file "$release_dir/images.env" -f "$release_dir/compose.yaml")
"${compose[@]}" config --quiet
gzip -dc "$release_dir/images.tar.gz" | docker load
web_image=$(sed -n 's/^WEB_IMAGE=//p' "$release_dir/images.env")
site_address=$(sed -n 's/^SITE_ADDRESS=//p' "$deploy_root/.env")
# A second Compose web container would collide with the running web's fixed IP.
docker run --rm --network none -e "SITE_ADDRESS=$site_address" \
  -v "$release_dir/Caddyfile:/etc/caddy/Caddyfile:ro" "$web_image" \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

previous_release=""
if [[ -L "$deploy_root/current" ]]; then
  previous_release=$(readlink -f "$deploy_root/current")
  old_compose=(docker compose --project-name "$project_name" --env-file "$deploy_root/.env" --env-file "$previous_release/images.env" -f "$previous_release/compose.yaml")
  "${old_compose[@]}" stop app
  "${old_compose[@]}" exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysqldump -u"$MYSQL_USER" --single-transaction --no-tablespaces "$MYSQL_DATABASE"' \
    | gzip > "$deploy_root/backups/$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
fi

# Failure leaves the current symlink unchanged. Schema changes cannot be
# automatically undone by restarting an old image; inspect before rolling back.
trap 'echo "Deployment failed; inspect docker compose logs. Previous release: ${previous_release:-none}" >&2' ERR
"${compose[@]}" up -d --wait --wait-timeout 240 mysql redis
"${compose[@]}" run --rm --no-deps --entrypoint /usr/local/bin/migrate app
"${compose[@]}" exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql --default-character-set=utf8mb4 -u"$MYSQL_USER" "$MYSQL_DATABASE"' < "$release_dir/communities.sql"
"${compose[@]}" up -d --wait --wait-timeout 120 app web
"${compose[@]}" exec -T web wget -q -O /dev/null http://app:8080/api/v1/communities

if [[ -n "$previous_release" && "$previous_release" != "$release_dir" ]]; then
  ln -sfn "$previous_release" "$deploy_root/previous"
fi
ln -sfn "$release_dir" "$deploy_root/current"
"${compose[@]}" ps
printf 'Release started. Verify public HTTPS and run deploy/smoke.py before declaring the site ready.\n'
