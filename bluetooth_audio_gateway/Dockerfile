ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:latest
FROM ${BUILD_FROM}

LABEL \
    io.hass.name="Bluetooth Audio Gateway" \
    io.hass.description="Bluetooth audio bridge for Home Assistant" \
    io.hass.type="addon"

# Installation des dépendances CRITIQUES
RUN apk update && apk add --no-cache \
    bluez \
    bluez-deprecated \
    bluez-libs \
    dbus \
    python3 \
    py3-pip \
    py3-dbus \
    py3-gobject3 \
    alsa-utils \
    alsa-lib \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    ffmpeg \
    curl \
    bash \
    git \
    gcc \
    musl-dev \
    python3-dev \
    linux-headers

# Installation de BlueALSA (remplace pipewire-spa-bluez)
RUN apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community \
    bluealsa \
    bluez-alsa-utils

# Dépendances Python pour l'API web
RUN apk add --no-cache \
    py3-flask \
    py3-flask-cors

# Copie des fichiers
COPY run.sh /
COPY api /api/
COPY www /www/

RUN chmod a+x /run.sh
EXPOSE 3000
CMD [ "/run.sh" ]