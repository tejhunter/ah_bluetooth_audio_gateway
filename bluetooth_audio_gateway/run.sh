#!/usr/bin/env bashio

# Arrêter le script en cas d'erreur
set -e

# Charger la configuration de l'add-on
DEVICE_ADDRESS=$(bashio::config 'device_address')

bashio::log.info "Initialisation du Bluetooth Audio Gateway..."

# IMPORTANT : D-Bus et bluetoothd sont déjà en cours d'exécution sur l'hôte.
# Nous n'avons PAS besoin de les redémarrer. Attendre qu'ils soient prêts.
sleep 5

# Activer l'adaptateur Bluetooth hci0 et le rendre visible
bashio::log.info "Activation de l'adaptateur Bluetooth hci0..."
hciconfig hci0 up || {
    bashio::log.error "Échec de l'activation de hci0. Vérifiez les permissions Bluetooth."
    exit 1
}
hciconfig hci0 piscan || bashio::log.warning "Le mode 'piscan' a peut-être échoué (peut être normal)."

# Si une adresse MAC est configurée, tenter la connexion
if [ -n "${DEVICE_ADDRESS}" ]; then
    bashio::log.info "Tentative de connexion à ${DEVICE_ADDRESS}..."
    
    # S'assurer que l'appareil est appairé/trusté, puis se connecter
    echo -e "trust ${DEVICE_ADDRESS}\nconnect ${DEVICE_ADDRESS}" | bluetoothctl
    sleep 8
    
    # Vérifier l'état de la connexion
    CONNECTION_STATUS=$(echo "info ${DEVICE_ADDRESS}" | bluetoothctl | grep -c "Connected: yes")
    if [ "${CONNECTION_STATUS}" -eq 1 ]; then
        bashio::log.info "Connexion Bluetooth établie avec succès."
    else
        bashio::log.warning "La connexion a peut-être échoué. Vérifiez que l'appareil est allumé et appairé."
    fi
fi

# ========== SECTION CRITIQUE : DÉMARRAGE DE BLUEALSA ==========
bashio::log.info "Démarrage du daemon BlueALSA..."

# Arrêter proprement tout processus bluealsa existant
pkill -9 bluealsa 2>/dev/null || true
sleep 2

# Créer le répertoire pour BlueALSA avec les bonnes permissions
mkdir -p /var/run/bluealsa
chown -R root:audio /var/run/bluealsa 2>/dev/null || true
chmod 775 /var/run/bluealsa

# Créer aussi le répertoire alternatif
mkdir -p /tmp/bluealsa
chmod 777 /tmp/bluealsa

# Démarrer bluealsa avec D-Bus désactivé et socket explicite
# L'option --disable-dbus résout l'erreur "Couldn't acquire D-Bus name"
# L'option -S spécifie le socket pour éviter les problèmes de permissions
bluealsa --disable-dbus -p a2dp-sink -i hci0 -S /tmp/bluealsa/socket &
BLUEALSA_PID=$!
sleep 5

# Vérification robuste du démarrage
if kill -0 $BLUEALSA_PID 2>/dev/null; then
    bashio::log.info "✅ BlueALSA daemon actif (PID: $BLUEALSA_PID)"
    
    # Vérifier que le socket est créé
    if [ -S "/tmp/bluealsa/socket" ]; then
        bashio::log.info "✅ Socket BlueALSA détecté: /tmp/bluealsa/socket"
        # Tester avec bluealsa-aplay
        if command -v bluealsa-aplay &> /dev/null; then
            bashio::log.info "Test bluealsa-aplay..."
            timeout 3 bluealsa-aplay -L 2>&1 | head -5
        fi
    else
        bashio::log.warning "⚠️  Socket BlueALSA non trouvé. Essai sans option -S..."
        pkill -9 bluealsa 2>/dev/null || true
        bluealsa --disable-dbus -p a2dp-sink -i hci0 &
        sleep 3
    fi
else
    bashio::log.error "❌ BlueALSA daemon n'a pas pu démarrer"
    # Essayer avec debug (option correcte)
    bashio::log.info "Tentative avec debug..."
    bluealsa --disable-dbus -p a2dp-sink -i hci0 --verbose &
    sleep 5
fi

# Vérifier les processus
ps aux | grep -E "bluealsa|bluez" | grep -v grep || true

# Démarrer le serveur API Python
bashio::log.info "Démarrage du serveur API Flask..."

# Vérifier que le fichier existe
if [ ! -f "/api/server.py" ]; then
    bashio::log.error "ERREUR : /api/server.py introuvable !"
    exit 1
fi

# Lancer le serveur Flask (remplace le processus actuel)
exec python3 /api/server.py