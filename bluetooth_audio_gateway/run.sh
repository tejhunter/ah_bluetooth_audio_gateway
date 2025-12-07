#!/usr/bin/env bashio
set -e
exec 2>&1  # Redirige tous les logs d'erreur vers la sortie standard

bashio::log.info "=== DÉBUT DU DIAGNOSTIC BLUETOOTH AUDIO GATEWAY ==="

# === ÉTAPE 1: AUDIT COMPLET DU SYSTÈME ===
bashio::log.info "[1/5] Audit du système et des paquets installés..."
bashio::log.info "Liste des paquets 'bluez' et 'bluealsa' installés :"
apk list --installed | grep -i blue 2>/dev/null || bashio::log.warning "Aucun paquet 'blue' trouvé."

bashio::log.info "Recherche de tous les binaires liés au Bluetooth :"
find /usr -type f -name "*blue*" -o -name "*bluetooth*" 2>/dev/null | sort

# === ÉTAPE 2: TENTATIVE FORCÉE D'INSTALLATION BLUETOOTH ===
bashio::log.info "[2/5] Installation forcée des paquets Bluetooth..."
bashio::log.info "Installation de bluez bluez-deprecated bluez-libs bluez-openrc..."
if apk add --no-cache --force-overwrite bluez bluez-deprecated bluez-libs bluez-openrc 2>/dev/null; then
    bashio::log.info "✅ Paquets Bluetooth installés."
    # Vérification immédiate
    if [ -f "/usr/lib/bluetooth/bluetoothd" ]; then
        BLUETOOTHD_PATH="/usr/lib/bluetooth/bluetoothd"
        bashio::log.info "✅ bluetoothd trouvé dans /usr/lib/bluetooth/"
    elif [ -f "/usr/sbin/bluetoothd" ]; then
        BLUETOOTHD_PATH="/usr/sbin/bluetoothd"
    else
        BLUETOOTHD_PATH=$(find /usr -type f -name "bluetoothd" 2>/dev/null | head -1)
    fi
else
    bashio::log.error "❌ Échec de l'installation des paquets Bluetooth."
fi

# === ÉTAPE 3: VÉRIFICATION BLUEALSA (COMPILATION) ===
bashio::log.info "[3/5] Vérification de BlueALSA (compilé depuis les sources)..."
# Chercher dans les emplacements d'installation standards
BLUEALSA_PATHS=(
    "/usr/bin/bluealsa"
    "/usr/local/bin/bluealsa"
    "/usr/sbin/bluealsa"
)
BLUEALSA_FOUND=""
for path in "${BLUEALSA_PATHS[@]}"; do
    if [ -f "$path" ]; then
        BLUEALSA_FOUND="$path"
        bashio::log.info "✅ BlueALSA trouvé : $path"
        ls -la "$path"
        # Tester l'exécution
        if "$path" --version 2>&1 | head -1; then
            bashio::log.info "✅ BlueALSA s'exécute correctement."
        fi
        break
    fi
done

if [ -z "$BLUEALSA_FOUND" ]; then
    bashio::log.error "❌ Aucun binaire BlueALSA trouvé."
    bashio::log.info "Recherche étendue dans tout le système..."
    find / -type f -name "bluealsa" 2>/dev/null | head -5
fi

# === ÉTAPE 4: DÉMARRAGE CONDITIONNEL DES SERVICES ===
bashio::log.info "[4/5] Démarrage conditionnel des services..."
# Démarrer bluetoothd si trouvé
if [ -n "$BLUETOOTHD_PATH" ] && [ -x "$BLUETOOTHD_PATH" ]; then
    bashio::log.info "Démarrage de bluetoothd depuis $BLUETOOTHD_PATH"
    # Démarrer en arrière-plan et capturer la sortie
    $BLUETOOTHD_PATH --nodetach --debug &
    BLUETOOTHD_PID=$!
    sleep 5
    if ps -p $BLUETOOTHD_PID > /dev/null 2>&1; then
        bashio::log.info "✅ bluetoothd en cours d'exécution (PID: $BLUETOOTHD_PID)"
    else
        bashio::log.warning "⚠️  bluetoothd peut avoir échoué à démarrer."
    fi
fi

# Démarrer BlueALSA si trouvé
if [ -n "$BLUEALSA_FOUND" ] && [ -x "$BLUEALSA_FOUND" ]; then
    bashio::log.info "Démarrage de BlueALSA depuis $BLUEALSA_FOUND"
    $BLUEALSA_FOUND --profile=a2dp-sink --profile=a2dp-source &
    BLUEALSA_PID=$!
    sleep 3
    if pgrep -x "bluealsa" > /dev/null; then
        bashio::log.info "✅ BlueALSA en cours d'exécution."
        # Tester bluealsa-aplay
        if command -v bluealsa-aplay >/dev/null 2>&1; then
            bashio::log.info "Test de bluealsa-aplay :"
            bluealsa-aplay --list-devices 2>&1 || true
        fi
    else
        bashio::log.warning "⚠️  BlueALSA n'a pas démarré."
        # Essayer en mode déverminage
        bashio::log.info "Tentative en mode debug..."
        $BLUEALSA_FOUND --profile=a2dp-sink --verbose 2>&1 &
        sleep 2
    fi
fi

# === ÉTAPE 5: DÉMARRAGE DE L'API QUOI QU'IL ARRIVE ===
bashio::log.info "[5/5] Préparation du démarrage de l'API Flask..."
bashio::log.info "État final du système :"
echo "=== PROCESSUS EN COURS ==="
ps aux | grep -E "(blue|dbus)" || true
echo "=== PORTS EN ÉCOUTE ==="
netstat -tuln 2>/dev/null | grep :3000 || true

if [ -f "/api/server.py" ]; then
    bashio::log.info "========================================"
    bashio::log.info "🚀 DÉMARRAGE DE L'API FLASK SUR LE PORT 3000"
    bashio::log.info "========================================"
    # Cette commande ne retourne pas en cas de succès
    exec python3 /api/server.py
else
    bashio::log.error "FATAL: Fichier /api/server.py introuvable."
    exit 1
fi