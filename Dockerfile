FROM debian:stable-slim

RUN apt-get update && \
    apt-get install -y rsync bash ca-certificates sqlite3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backup.sh /app/backup.sh
COPY restore.sh /app/restore.sh

RUN chmod +x /app/backup.sh /app/restore.sh

ENTRYPOINT ["/bin/bash"]