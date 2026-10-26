FROM node:24-alpine AS build
WORKDIR /src
RUN npm install -g pnpm@11.22.0
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run typecheck && pnpm run lint && pnpm test \
 && pnpm run contract:check && pnpm run build

FROM caddy:2.11.7-alpine@sha256:d8542f48d34a9cf4e4c11a478865229840e87e4c96ea3f439101f31a5d35f75f
COPY --from=build /src/dist /srv
