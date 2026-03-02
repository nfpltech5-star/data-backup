FROM alpine:latest

RUN apk add --no-cache bash samba-client tzdata sqlite

ENV TZ=Asia/Kolkata

WORKDIR /app

COPY backup.sh /app/backup.sh
COPY restore.sh /app/restore.sh

RUN chmod +x /app/backup.sh
RUN chmod +x /app/restore.sh

CMD ["/bin/bash"]