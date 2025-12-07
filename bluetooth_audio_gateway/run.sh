#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway (BlueALSA)..."
sleep 2

# === 1. UTILISATION DU DBUS SYSTÈME DÉJÀ PRÉSENT ===
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
bashio::log.info "Utilisation du bus D-Bus système existant..."

if [ ! -S "$DBUS_SYSTEM_BUS_ADDRESS" ]; then
    bashio::log.warning "⚠️  Socket D-Bus principal non trouvé. Recherche d'alternatives..."
    if [ -S "/var/run/dbus/system_bus_socket" ]; then
        export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/var/run/dbus/system_bus_socket"
        bashio::log.info "Socket D-Bus trouvé sur /var/run/dbus/system_bus_socket"
    else
        bashio::log.error "❌ Aucun socket D-Bus système trouvé."
        exit 1
    fi
fi

# === 2. DÉMARRAGE SERVICE BLUETOOTH ===
bashio::log.info "Démarrage du démon Bluetooth (bluetoothd)..."
# Démarrer bluetoothd simplement
bluetoothd --nodetach &
BLUETOOTHD_PID=$!
sleep 3

# === 3. ACTIVATION ADAPTATEUR BLUETOOTH ===
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Mode 'piscan' non critique."
sleep 2

# === 4. DÉMARRAGE DU DÉMON BLUEALSA ===
bashio::log.info "Démarrage du démon BlueALSA (profil A2DP)..."
# Démarrer BlueALSA avec le profil audio stéréo standard
bluealsa --profile=a2dp-sink --profile=a2dp-source &
BLUEALSA_PID=$!
sleep 3

# Vérification rapide
if pgrep -x "bluealsa" > /dev/null; then
    bashio::log.info "✅ BlueALSA est en cours d'exécution."
else
    bashio::log.error "❌ BlueALSA n'a pas démarré correctement."
    exit 1
fi

# === 5. VÉRIFICATION DES PÉRIPHÉRIQUEs BLUEALSA ===
bashio::log.info "Vérification de l'état BlueALSA..."
if command -v bluealsa-aplay &> /dev/null; then
    bashio::log.info "Liste des périphériques détectés par BlueALSA:"
    bluealsa-aplay --list-devices 2>/dev/null || bashio::log.warning "Aucun périphérique pour l'instant."
else
    bashio::log.warning "bluealsa-aplay non trouvé."
fi

# === 6. CONFIGURATION AUDIO MINIMALE (ALSA) ===
bashio::log.info "Configuration de l'environnement ALSA..."
export ALSA_PCM_CARD="bluealsa"

# === 7. DÉMARRAGE SERVEUR API ===
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

# Log final
bashio::log.info "========================================"
bashio::log.info "✅ Bluetooth Audio Gateway opérationnel"
bashio::log.info "✅ Backend audio : BlueALSA"
bashio::log.info "✅ API disponible sur le port 3000"
bashio::log.info "========================================"

exec python3 /api/server.py