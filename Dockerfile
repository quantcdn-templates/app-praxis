# app-praxis — Praxis dashboard on Quant Cloud.
#
# Multi-stage build: stage 1 pulls the published Praxis dashboard image as
# a source layer; stage 2 carries the workspace onto the Quant app-node base
# so the runtime image inherits SMTP, tini, the /quant-entrypoint.d/ hook, and
# the EFS-friendly node user (UID 1000).
#
# Requires praxis-framework PR-1 (dashboard image base swap to bookworm-slim)
# to have landed and re-published the dashboard image.

ARG NODE_VERSION=22

# Stage 1: published Praxis dashboard image
FROM ghcr.io/steveworley/praxis-framework/dashboard:latest AS praxis

# Stage 2: Quant Node base
FROM ghcr.io/quantcdn-templates/app-node:${NODE_VERSION}

# Carry the pruned workspace tree intact.
# Layout under /app in the praxis image (per praxis-framework/dashboard/Dockerfile):
#   /app/package.json
#   /app/node_modules                       (hoisted workspace deps)
#   /app/packages/seed/{package.json,dist}
#   /app/packages/inference/{package.json,dist}
#   /app/packages/inference-quantcloud/{package.json,dist}
#   /app/dashboard/{package.json,dist,node_modules}
COPY --from=praxis --chown=node:node /app /app

# Quant entrypoint hook — runs before CMD via /usr/local/bin/docker-entrypoint.sh
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN find /quant-entrypoint.d -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

ENV PRAXIS_ROLE_HOME=/role \
    PRAXIS_INFERENCE_PROVIDER=quantcloud \
    HOST=0.0.0.0 \
    PORT=4321 \
    NODE_ENV=production

EXPOSE 4321

WORKDIR /app/dashboard
CMD ["node", "./dist/server/entry.mjs"]
