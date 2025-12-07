ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:latest
FROM ${BUILD_FROM}

LABEL \
    io.hass.name="Bluetooth Audio Gateway" \
    io.hass.description="Bluetooth audio bridge for Home Assistant" \
    io.hass.type="addon"

# 1. Installation des dépendances critiques de base
RUN apk update && apk add --no-cache \
    bluez \
    bluez-deprecated \
    bluez-libs \
    bluez-openrc \
    dbus \
    python3 \
    py3-pip \
    py3-dbus \
    py3-gobject3 \
    alsa-utils \
    alsa-lib \
    curl \
    bash \
    git

# 2. Installation de BlueALSA depuis le dépôt 'edge' d'Alpine (où il est disponible)
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && apk add --no-cache bluez-alsa-utils

# 3. Dépendances Python pour l'API web
RUN apk add --no-cache \
    py3-flask \
    py3-flask-cors

# Copie des fichiers de l'add-on
COPY run.sh /
COPY api /api/
COPY www /www/

RUN chmod a+x /run.sh
EXPOSE 3000
CMD [ "/run.sh" ]