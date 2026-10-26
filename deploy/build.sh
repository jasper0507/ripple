#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
frontend_dir=${1:-"$repo_dir/../ripple_frontend"}
version=${2:-"$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$repo_dir" rev-parse --short HEAD)"}
[[ $version =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,100}$ ]] || { echo "Invalid release version" >&2; exit 1; }
[[ -f "$frontend_dir/pnpm-lock.yaml" ]] || { echo "Frontend checkout not found: $frontend_dir" >&2; exit 1; }
release_dir="$repo_dir/dist/releases/$version"
[[ ! -e "$release_dir" ]] || { echo "Release already exists: $release_dir" >&2; exit 1; }

docker build --platform linux/amd64 -t "ripple-backend:$version" -f "$repo_dir/Dockerfile" "$repo_dir"
docker build --platform linux/amd64 -t "ripple-web:$version" -f "$repo_dir/deploy/frontend.Dockerfile" "$frontend_dir"
docker pull --platform linux/amd64 mysql:8.4
docker pull --platform linux/amd64 redis:7.4-alpine
docker tag mysql:8.4 "ripple-mysql:$version"
docker tag redis:7.4-alpine "ripple-redis:$version"

mkdir -p "$release_dir"
cp "$repo_dir"/deploy/{compose.yaml,Caddyfile,mysql.cnf,communities.sql,env.example,apply.sh} "$release_dir/"
printf 'APP_IMAGE=ripple-backend:%s\nWEB_IMAGE=ripple-web:%s\nMYSQL_IMAGE=ripple-mysql:%s\nREDIS_IMAGE=ripple-redis:%s\n' \
  "$version" "$version" "$version" "$version" > "$release_dir/images.env"
{
  printf 'Release: %s\nBackend: ' "$version"
  git -C "$repo_dir" rev-parse HEAD
  git -C "$repo_dir" status --short
  printf 'Frontend: '
  git -C "$frontend_dir" rev-parse HEAD
  git -C "$frontend_dir" status --short
  docker image inspect "ripple-backend:$version" "ripple-web:$version" "ripple-mysql:$version" "ripple-redis:$version" \
    --format '{{json .RepoTags}} {{.Id}} {{json .RepoDigests}}'
} > "$release_dir/sources.txt"
docker save "ripple-backend:$version" "ripple-web:$version" "ripple-mysql:$version" "ripple-redis:$version" \
  | gzip -1 > "$release_dir/images.tar.gz"
printf 'Release ready: %s\n' "$release_dir"
