# Multi-arch: builds natively on the Pi (arm64) or via buildx elsewhere.
FROM python:3.12-slim

# ODBC Driver 18 for SQL Server + unixODBC (Debian bookworm, arm64-compatible)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg apt-transport-https ca-certificates unixodbc \
    && curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
    && apt-get purge -y curl gnupg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY consumer/ ./consumer/

# LANE and all connection env vars are supplied at runtime (compose / Jenkins).
ENTRYPOINT ["python", "-m", "consumer.main"]
