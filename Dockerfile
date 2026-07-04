# Builds natively on the Pi (arm64) - Jenkins runs on the Pi, so no buildx needed.
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

# src/ layout: the package lives at src/replicator/. Put src on the path so
# "python -m replicator.run_once" resolves.
COPY src/ ./src/
ENV PYTHONPATH=/app/src/consumer

# ON-DEMAND MODEL:
# The container runs IDLE (no timer loop). The laptop triggers one cycle via:
#     docker exec replicator-test python -m replicator.run_once
# so the main process just keeps the container alive and does nothing itself.
#
# (To revert to the self-timed loop, set this back to:
#   CMD ["python", "-m", "replicator.main"]  )
CMD ["sleep", "infinity"]
