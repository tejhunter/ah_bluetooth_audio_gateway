ARG BUILD_FROM
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
    bluez-openrc \
    dbus \
    python3 \
    py3-pip \
    py3-dbus \
    py3-gobject3 \
    alsa-utils \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    pipewire-spa-bluez \  # PAQUET CORRIGÉ ICI
    ffmpeg \
    curl \
    bash \
    git \
    gcc \
    musl-dev \
    python3-dev \
    linux-headers

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