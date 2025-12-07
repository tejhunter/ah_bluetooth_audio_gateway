from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import subprocess
import json
import os
import time
import dbus

app = Flask(__name__, static_folder='/www')
CORS(app)

# ========== ROUTES WEB ==========
@app.route('/')
def serve_index():
    return send_from_directory('/www', 'index.html')

@app.route('/<path:filename>')
def serve_static(filename):
    return send_from_directory('/www', filename)

# ========== FONCTIONS UTILITAIRES ==========
def get_device_details(mac_address):
    """Récupère les informations détaillées d'un appareil Bluetooth."""
    try:
        cmd = f"echo 'info {mac_address}' | bluetoothctl"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        output = result.stdout

        details = {
            'address': mac_address,
            'connected': 'Connected: yes' in output,
            'paired': 'Paired: yes' in output,
            'trusted': 'Trusted: yes' in output,
            'name': 'Name not found',
            'device_class': '0x000000',
            'icon': 'mdi:bluetooth',
            'is_ble': False  # Valeur par défaut
        }

        # Variables temporaires pour l'extraction
        uuids_found = []
        
        # Extraire le nom, la classe et les UUIDs
        for line in output.split('\n'):
            line = line.strip()
            if line.startswith('Name:'):
                details['name'] = line.split('Name:')[1].strip()
            elif line.startswith('Class:'):
                details['device_class'] = line.split('Class:')[1].strip()
                class_hex = details['device_class'].lower()
                if '0x2404' in class_hex:  # Audio/video
                    details['icon'] = 'mdi:speaker'
                elif '0x5a020c' in class_hex:  # Smartphone
                    details['icon'] = 'mdi:cellphone'
                elif '0x2508' in class_hex:  # Wearable
                    details['icon'] = 'mdi:watch'
                elif '0x1f00' in class_hex:  # Computer
                    details['icon'] = 'mdi:laptop'
            elif 'UUID:' in line:
                # Extraire l'UUID (généralement entre parenthèses)
                if '(' in line and ')' in line:
                    uuid = line.split('(')[1].split(')')[0].strip().lower()
                    uuids_found.append(uuid)

        # Détection BLE basée sur les UUIDs trouvés
        if uuids_found:
            ble_uuids = ['fe95', 'fdab', 'fef3', 'a201']
            for uuid in uuids_found:
                if any(ble_uuid in uuid for ble_uuid in ble_uuids):
                    details['is_ble'] = True
                    # Pour les appareils BLE, ajuster l'icône
                    if details['icon'] == 'mdi:bluetooth':
                        details['icon'] = 'mdi:watch' if 'watch' in details['name'].lower() else 'mdi:bluetooth'
                    break
        
        return details
    except Exception as e:
        app.logger.error(f"Erreur get_device_details pour {mac_address}: {e}")
        return None
    

# ========== ENDPOINTS API ==========
@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint de test pour vérifier que le serveur fonctionne."""
    return jsonify({'status': 'ok', 'service': 'Bluetooth Audio Gateway'})

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Lister les appareils Bluetooth avec leur état."""
    try:
        # 1. Obtenir la liste brute des appareils connus
        list_result = subprocess.run(['bluetoothctl', 'devices'], 
                                   capture_output=True, text=True)
        
        app.logger.info(f"Sortie de bluetoothctl devices: {list_result.stdout}")
        
        devices = []
        
        for line in list_result.stdout.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                app.logger.info(f"Ligne parsée: {parts}")
                if len(parts) >= 3:
                    mac_address = parts[1]
                    details = get_device_details(mac_address)
                    if details:
                        devices.append(details)

        # 2. Trier : appareils connectés en premier
        devices.sort(key=lambda x: x['connected'], reverse=True)

        return jsonify({'success': True, 'devices': devices})

    except Exception as e:
        app.logger.error(f"Erreur lors du scan: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/connect', methods=['POST'])
def connect_device():
    """Connecter à un appareil Bluetooth."""
    try:
        data = request.get_json()
        address = data.get('address')
        app.logger.info(f"Connexion à: {address}")

        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # 1. Vérifier l'état
        info_cmd = f"echo 'info {address}' | bluetoothctl"
        info_result = subprocess.run(info_cmd, shell=True, 
                                   capture_output=True, text=True, timeout=5)
        info_output = info_result.stdout

        paired = 'Paired: yes' in info_output
        trusted = 'Trusted: yes' in info_output

        # 2. Gérer l'état incohérent (trusted mais pas paired)
        if not paired and trusted:
            app.logger.info("Correction état incohérent...")
            untrust_cmd = f"echo -e 'untrust {address}\\n' | bluetoothctl"
            subprocess.run(untrust_cmd, shell=True, capture_output=True, text=True)

        # 3. Appairage si nécessaire
        if not paired:
            app.logger.info("Lancement appairage...")
            subprocess.run(['bluetoothctl', 'agent', 'on'], capture_output=True)
            subprocess.run(['bluetoothctl', 'default-agent'], capture_output=True)
            
            pair_cmd = f"echo -e 'pair {address}\\n' | timeout 30 bluetoothctl"
            pair_result = subprocess.run(pair_cmd, shell=True, 
                                       capture_output=True, text=True, timeout=35)
            
            if 'Pairing successful' in (pair_result.stdout + pair_result.stderr):
                trust_cmd = f"echo -e 'trust {address}\\n' | bluetoothctl"
                subprocess.run(trust_cmd, shell=True, capture_output=True, text=True)
                time.sleep(2)

        # 4. Connexion principale
        app.logger.info(f"Tentative de connexion...")
        connect_cmd = f"echo -e 'connect {address}\\n' | timeout 15 bluetoothctl"
        result = subprocess.run(connect_cmd, shell=True, 
                              capture_output=True, text=True, timeout=20)
        
        time.sleep(3)

        # 5. Vérification finale
        final_info_cmd = f"echo 'info {address}' | bluetoothctl"
        final_info_result = subprocess.run(final_info_cmd, shell=True, 
                                         capture_output=True, text=True, timeout=5)
        final_output = final_info_result.stdout

        if 'Connected: yes' in final_output:
            app.logger.info(f"SUCCÈS : {address} connecté.")
            return jsonify({'success': True, 'message': f'Appareil connecté.'})
        else:
            error_msg = "Connexion échouée."
            if 'Device not available' in final_output:
                error_msg = "Appareil hors de portée."
            elif 'Profile not available' in final_output:
                error_msg = "Profil incompatible."
            
            app.logger.warning(f"ÉCHEC : {error_msg}")
            return jsonify({'success': False, 'error': error_msg}), 500

    except subprocess.TimeoutExpired:
        app.logger.error("Timeout")
        return jsonify({'success': False, 'error': 'Timeout'}), 500
    except Exception as e:
        app.logger.error(f"Erreur: {str(e)}")
        return jsonify({'success': False, 'error': f'Erreur interne: {str(e)}'}), 500

@app.route('/api/disconnect', methods=['POST'])
def disconnect_device():
    """Déconnecter un appareil Bluetooth."""
    try:
        data = request.get_json()
        address = data.get('address')
        
        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # Commande de déconnexion
        cmd = f"echo -e 'disconnect {address}\\n' | bluetoothctl"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        
        time.sleep(2)
        
        # Vérification
        info_cmd = f"echo 'info {address}' | bluetoothctl"
        info_result = subprocess.run(info_cmd, shell=True, capture_output=True, text=True, timeout=5)
        
        if 'Connected: no' in info_result.stdout:
            return jsonify({'success': True, 'message': 'Appareil déconnecté.'})
        else:
            return jsonify({'success': False, 'error': 'Échec déconnexion.'}), 500
            
    except Exception as e:
        app.logger.error(f"Erreur déconnexion: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/repair', methods=['POST'])
def repair_device():
    """Forcer un ré-appairage propre."""
    try:
        data = request.get_json()
        address = data.get('address')
        app.logger.info(f"Ré-appairage: {address}")

        # Nettoyer l'état existant
        cleanup_cmd = f"echo -e 'untrust {address}\\nremove {address}\\n' | bluetoothctl"
        subprocess.run(cleanup_cmd, shell=True, capture_output=True, text=True)
        time.sleep(3)

        # Redémarrer un appairage
        subprocess.run(['bluetoothctl', 'agent', 'on'], capture_output=True)
        subprocess.run(['bluetoothctl', 'default-agent'], capture_output=True)
        
        pair_cmd = f"echo -e 'pair {address}\\n' | timeout 30 bluetoothctl"
        pair_result = subprocess.run(pair_cmd, shell=True, capture_output=True, text=True, timeout=35)
        
        if 'Pairing successful' in (pair_result.stdout + pair_result.stderr):
            trust_cmd = f"echo -e 'trust {address}\\n' | bluetoothctl"
            subprocess.run(trust_cmd, shell=True, capture_output=True, text=True)
            time.sleep(2)
            
            return jsonify({'success': True, 'message': 'Ré-appairage réussi'})
        else:
            return jsonify({'success': False, 'error': 'Échec appairage'}), 500
            
    except Exception as e:
        app.logger.error(f"Erreur ré-appairage: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500
    

@app.route('/api/ble_connect', methods=['POST'])
def connect_ble_device():
    """Connecter à un appareil BLE (version simplifiée sans GLib)."""
    try:
        data = request.get_json()
        address = data.get('address')
        
        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # Utiliser bluetoothctl avec l'option --le (Low Energy)
        cmd = f"echo -e 'connect {address}\\n' | bluetoothctl --le"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        
        app.logger.info(f"Sortie BLE: {result.stdout[:200]}")
        
        if 'Connection successful' in result.stdout:
            return jsonify({'success': True, 'message': f'Connexion BLE à {address} établie.'})
        else:
            # Pour BLE, on peut aussi essayer avec gatttool
            ble_cmd = f"gatttool -b {address} --interactive"
            test_result = subprocess.run(
                f"echo 'exit' | {ble_cmd}", 
                shell=True, capture_output=True, text=True, timeout=10
            )
            
            if 'Connection successful' in test_result.stdout:
                return jsonify({'success': True, 'message': 'Connexion BLE (via gatttool) établie.'})
            else:
                return jsonify({
                    'success': False, 
                    'error': 'Échec connexion BLE. L\'appareil nécessite peut-être une app spécifique.',
                    'details': result.stderr[:200]
                }), 500
                
    except Exception as e:
        app.logger.error(f"Erreur BLE: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500
    



# ========== DÉMARRAGE ==========
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)