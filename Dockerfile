# Use Python base image for more reliable ChromaDB deployment
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install ChromaDB with compatible NumPy version
RUN pip install numpy==1.26.4 && \
    pip install chromadb==0.5.0

# Set environment variables
ENV CHROMA_HOST=0.0.0.0
ENV CHROMA_PORT=8000
ENV IS_PERSISTENT=TRUE
ENV ANONYMIZED_TELEMETRY=FALSE

# Create data directory for persistence
RUN mkdir -p /chroma/data

# Set working directory
WORKDIR /chroma

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/api/v1/heartbeat || exit 1

# Start ChromaDB server using Python module
CMD ["python", "-m", "chromadb.cli.cli", "run", "--host", "0.0.0.0", "--port", "8000", "--path", "/chroma/data"]