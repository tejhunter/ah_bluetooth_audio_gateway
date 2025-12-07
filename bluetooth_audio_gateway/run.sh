#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."
sleep 2

# === 1. DÉMARRAGE DBUS (Critique pour le bus système) ===
bashio::log.info "Démarrage de D-Bus..."
dbus-daemon --system --fork
sleep 3

# === 2. DÉMARRAGE SERVICE BLUETOOTH (OpenRC) ===
bashio::log.info "Démarrage du service Bluetooth système..."
rc-service bluetooth start 2>/dev/null || {
    bashio::log.warning "Service bluetooth OpenRC non trouvé. Lancement manuel..."
    bluetoothd --debug &
    BLUETOOTHD_PID=$!
}
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

bashio::log.info "Démarrage de pipewire-pulse (compatibilité PulseAudio)..."
pipewire-pulse &

sleep 6  # Temps d'initialisation

# === 5. VÉRIFICATION PIPEWIRE ===
if pactl info 2>&1 | grep -q "PipeWire"; then
    bashio::log.info "✅ PipeWire est opérationnel."
    # Log supplémentaire utile
    pactl info | grep "Server Name" | head -1
else
    bashio::log.error "❌ PipeWire ne semble pas fonctionner."
    # On continue malgré tout, le serveur API peut démarrer
fi

# === 6. DÉMARRAGE SERVEUR API ===
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi
exec python3 /api/server.py