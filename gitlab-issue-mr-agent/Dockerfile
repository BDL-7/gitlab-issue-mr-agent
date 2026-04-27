FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source
COPY . .

# Expose FastAPI port
EXPOSE 8000

# Run the agent server
CMD ["uvicorn", "agent.server:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "info"]
