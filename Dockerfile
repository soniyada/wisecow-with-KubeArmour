FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository universe && \
    apt-get update && \
    apt-get install -y fortune-mod cowsay netcat-openbsd && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY wisecow.sh .

RUN chmod +x wisecow.sh

ENV PATH="$PATH:/usr/games"

EXPOSE 4499

CMD ["./wisecow.sh"]
