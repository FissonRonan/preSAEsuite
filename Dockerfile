FROM debian:13

# Installation des dépendances minimales requises
RUN apt-get update && apt-get install -y \
    ruby \
    iproute2 \
    procps \
    systemd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY audit.rb .
RUN chmod +x audit.rb

# Point d'entrée pour passer les arguments docker directement au script
ENTRYPOINT ["ruby", "audit.rb"]