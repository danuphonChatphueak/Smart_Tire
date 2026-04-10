# ============================================================
# Smart-Tire Backend — Docker Image
# Base: Python 3.11 slim + PyTorch CPU
# ============================================================

# ---------- Stage 1: Builder (install deps) ----------
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY requirements.txt .

# Install PyTorch CPU first (smaller image, no CUDA)
RUN pip install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cpu

# Install remaining dependencies
RUN pip install --no-cache-dir -r requirements.txt


# ---------- Stage 2: Runtime ----------
FROM python:3.11-slim AS runtime

# OpenCV & system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed Python packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY app/ ./app/
COPY requirements.txt .

# Create uploads directory
RUN mkdir -p uploads

# ---- Model files ----
# Models are copied from the local app/models directory.
# Make sure .pt / .pth files exist before building:
#   app/models/det_tire_code.pt
#   app/models/rec_tire_code.pth
#   app/models/depth_tire.pt

# ---- Environment Variables ----
# Optional (have defaults in config.py):
#   infer_device=cpu, det_model_path, rec_model_path, depth_model_path
ENV PYTHONUNBUFFERED=1
ENV infer_device=cpu

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import httpx; r = httpx.get('http://localhost:8000/docs'); assert r.status_code == 200" || exit 1

# Start server
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
