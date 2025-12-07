#!/usr/bin/env bashio
set -e

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."
sleep 5

# Activer l'adaptateur Bluetooth (inchangé)
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Le mode 'piscan' a peut-être échoué."

# === NOUVELLE SECTION : Démarrer l'environnement audio PipeWire ===
bashio::log.info "Configuration de l'environnement PipeWire..."

# 1. S'assurer que le répertoire de runtime D-Bus utilisateur existe
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"

# 2. Démarrer le service system-wide PipeWire (nécessaire pour certains liens)
bashio::log.info "Démarrage du service PipeWire système..."
pipewire &

# 3. Démarrer WirePlumber (gestionnaire de session/politiques)
bashio::log.info "Démarrage du gestionnaire de session WirePlumber..."
wireplumber &

# 4. Démarrer l'émulateur PulseAudio de PipeWire
#    Cela permet aux applications utilisant libpulse (comme votre serveur API) de fonctionner.
bashio::log.info "Démarrage de pipewire-pulse (compatibilité PulseAudio)..."
pipewire-pulse &

sleep 8  # Donner le temps aux services de démarrer

# Vérification rapide
if pactl info 2>&1 | grep -q "PipeWire"; then
    bashio::log.info "✅ PipeWire est en cours d'exécution et opérationnel."
    pactl info | head -5
else
    bashio::log.error "❌ PipeWire/PulseAudio ne semble pas fonctionner."
    bashio::log.info "Tentative de démarrage alternatif via D-Bus..."
    dbus-run-session -- pipewire &
    sleep 5
fi
# === FIN DE LA NOUVELLE SECTION ===

# Démarrage du serveur API Flask (inchangé)
bashio::log.info "Démarrage du serveur API Flask..."
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi
exec python3 /api/server.py