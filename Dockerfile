FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www
ENV HOME=/var/www

COPY script.sh /usr/local/bin/script.sh
RUN chmod +x /usr/local/bin/script.sh

EXPOSE 8080

CMD ["/bin/bash", "-c", "/usr/local/bin/script.sh alex & exec python3 -u -m http.server 8080"]
