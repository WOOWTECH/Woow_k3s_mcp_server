# Stage 1: Build frontend
FROM node:20-alpine AS frontend-builder
WORKDIR /build
COPY frontend/package.json frontend/
RUN cd frontend && npm install --production=false
COPY frontend/ frontend/
RUN cd frontend && npm run build

# Stage 2: Python runtime
FROM python:3.12-slim
WORKDIR /app

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install mcp-admin-core
COPY mcp-admin-core/ /tmp/mcp-admin-core/
RUN pip install --no-cache-dir /tmp/mcp-admin-core/ && rm -rf /tmp/mcp-admin-core/

# Install k3s-mcp-admin
COPY pyproject.toml /tmp/k3s-app/pyproject.toml
COPY k3s_mcp_admin/ /tmp/k3s-app/k3s_mcp_admin/
RUN pip install --no-cache-dir /tmp/k3s-app/ && rm -rf /tmp/k3s-app/

# Copy frontend build
COPY --from=frontend-builder /build/frontend/dist /app/static

# Create data directory
RUN mkdir -p /data

EXPOSE 9001
CMD ["uvicorn", "k3s_mcp_admin.main:app", "--host", "0.0.0.0", "--port", "9001"]
