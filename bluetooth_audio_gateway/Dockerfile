ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:latest
FROM ${BUILD_FROM}

LABEL \
    io.hass.name="Bluetooth Audio Gateway" \
    io.hass.description="Bluetooth audio bridge for Home Assistant" \
    io.hass.type="addon"

# 1. Installation des dépendances critiques (base)
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

# 2. Installation des dépendances pour compiler BlueALSA
RUN apk add --no-cache --virtual .build-deps \
    git \
    make \
    gcc \
    musl-dev \
    autoconf \
    automake \
    libtool \
    pkgconf \
    alsa-lib-dev \
    dbus-dev \
    glib-dev \
    bluez-dev \
    libbsd-dev \
    sbc-dev

# 3. Compilation et installation de BlueALSA depuis les sources
RUN cd /tmp && \
    git clone https://github.com/Arkq/bluez-alsa.git && \
    cd bluez-alsa && \
    autoreconf --install && \
    mkdir build && cd build && \
    ../configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-hcitop \
        --disable-aac \
        --disable-ofono \
        --disable-debug && \
    make && \
    make install

# 4. Nettoyage des outils de compilation
RUN apk del .build-deps && \
    rm -rf /tmp/bluez-alsa

# 5. Dépendances Python pour l'API web
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