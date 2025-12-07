#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."
sleep 2

# === 1. UTILISATION DU DBUS SYSTÈME EXISTANT (SUPPRIMER L'ANCIENNE LIGNE) ===
# NE PAS EXÉCUTER : dbus-daemon --system --fork
# Le bus système est déjà disponible. S'assurer que les outils l'utilisent.
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=/run/dbus/system_bus_socket"
bashio::log.info "Utilisation du bus D-Bus système existant..."

# === 2. DÉMARRAGE SERVICE BLUETOOTH ===
bashio::log.info "Démarrage du service Bluetooth..."
# Tenter de démarrer via OpenRC, sinon lancer bluetoothd directement.
if command -v rc-service >/dev/null 2>&1 && rc-service bluetooth start 2>/dev/null; then
    bashio::log.info "Service Bluetooth démarré via OpenRC."
else
    bashio::log.warning "Lancement manuel de bluetoothd..."
    bluetoothd --debug &
    BLUETOOTHD_PID=$!
fi
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
export XDG_RUNTIME_DIR="/run/user/0"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"

# Démarrer PipeWire et ses composants
bashio::log.info "Démarrage de PipeWire..."
pipewire &

bashio::log.info "Démarrage de WirePlumber..."
wireplumber &

bashio::log.info "Démarrage de pipewire-pulse..."
pipewire-pulse &

sleep 6  # Temps d'initialisation

# === 5. VÉRIFICATION PIPEWIRE ===
if pactl info 2>&1 | grep -q "PipeWire"; then
    bashio::log.info "✅ PipeWire est opérationnel."
    pactl info | grep "Server Name" | head -1
else
    bashio::log.warning "⚠️  PipeWire ne semble pas actif (peut être normal si démarré plus tard)."
fi

# === 6. DÉMARRAGE SERVEUR API ===
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi
exec python3 /api/server.py