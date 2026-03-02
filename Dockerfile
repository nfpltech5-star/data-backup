FROM alpine:latest

RUN apk add --no-cache bash samba-client tzdata sqlite

ENV TZ=Asia/Kolkata

WORKDIR /app

COPY backup.sh /app/backup.sh
RUN chmod +x /app/backup.sh

CMD ["/bin/bash"]