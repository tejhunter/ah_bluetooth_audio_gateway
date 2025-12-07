#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."
sleep 2

# === 1. UTILISATION DU DBUS SYSTÈME DÉJÀ PRÉSENT ===
# Le bus système D-Bus est fourni par le système hôte (Home Assistant OS)
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
bashio::log.info "Utilisation du bus D-Bus système existant..."

# Vérification que le socket est accessible
if [ ! -S "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    bashio::log.warning "⚠️  Le socket D-Bus système n'est pas trouvé. Vérification des alternatives..."
    # Recherche d'autres sockets potentiels
    if [ -S "/var/run/dbus/system_bus_socket" ]; then
        export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"
        bashio::log.info "Socket D-Bus trouvé sur /var/run/dbus/system_bus_socket"
    else
        bashio::log.error "❌ Aucun socket D-Bus système trouvé. L'add-on ne peut pas fonctionner."
        exit 1
    fi
fi

# === 2. DÉMARRAGE SERVICE BLUETOOTH ===
bashio::log.info "Démarrage du service Bluetooth..."
# Vérifier si bluez est installé
if ! command -v bluetoothd &> /dev/null; then
    bashio::log.error "bluetoothd non trouvé. Installation de bluez-deprecated..."
    apk add --no-cache bluez-deprecated
fi

# Démarrer bluetoothd
bluetoothd --debug --nodetach &
BLUETOOTHD_PID=$!
sleep 3

# === 3. ACTIVATION ADAPTATEUR BLUETOOTH ===
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Mode 'piscan' non critique."

# === 4. CONFIGURATION ENVIRONNEMENT PIPEWIRE ===
bashio::log.info "Configuration de l'environnement PipeWire..."
export XDG_RUNTIME_DIR="/tmp/pipewire"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"

# Variables d'environnement pour éviter les erreurs D-Bus
export DISPLAY=:0
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR"

# Démarrer PipeWire et ses composants
bashio::log.info "Démarrage de PipeWire..."
pipewire &
sleep 2

bashio::log.info "Démarrage de WirePlumber..."
wireplumber &
sleep 2

bashio::log.info "Démarrage de pipewire-pulse..."
pipewire-pulse &
sleep 4

# === 5. VÉRIFICATION PIPEWIRE ===
if pactl info 2>&1 | grep -q "PipeWire"; then
    bashio::log.info "✅ PipeWire est opérationnel."
    pactl info | grep "Server Name" | head -1
else
    bashio::log.warning "⚠️  PipeWire ne semble pas actif, tentative de redémarrage..."
    pkill -f pipewire
    pipewire &
    pipewire-pulse &
    sleep 3
fi

# === 6. ACTIVER LE MODULE BLUETOOTH DE PIPEWIRE ===
bashio::log.info "Chargement du module Bluetooth PipeWire..."
pactl load-module module-bluetooth-discover || {
    bashio::log.warning "Module Bluetooth déjà chargé ou erreur de chargement"
}

# === 7. VÉRIFICATION DES PERIPHERIQUES ===
bashio::log.info "Liste des périphériques audio disponibles:"
pactl list sinks short

bashio::log.info "Liste des cartes audio:"
pactl list cards short

# === 8. DÉMARRAGE SERVEUR API ===
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

exec python3 /api/server.py