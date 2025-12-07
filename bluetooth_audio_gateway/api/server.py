from flask import Flask, jsonify, send_from_directory, request
from flask_cors import CORS
import subprocess
import json
import os
import time
import tempfile
import wave
import math
import struct
import shutil

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

def _run_cmd(cmd, timeout=30, shell=False):
    """Exécute une commande et retourne (succès, sortie)."""
    try:
        result = subprocess.run(cmd, shell=shell, capture_output=True, text=True, timeout=timeout)
        combined = (result.stdout + '\n' + result.stderr).strip()
        return result.returncode == 0, combined
    except subprocess.TimeoutExpired:
        return False, 'Timeout'
    except Exception as e:
        return False, str(e)

def _which(cmd):
    """Vérifie si une commande existe."""
    return shutil.which(cmd) is not None

def _generate_tone_wav(path, duration=1.0, freq=440.0, volume=0.5, samplerate=44100):
    """Génère un fichier WAV mono d'un ton sinusoidal."""
    n_samples = int(samplerate * duration)
    amplitude = int(32767 * max(0.0, min(1.0, volume)))

    with wave.open(path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16 bits
        wf.setframerate(samplerate)

        for i in range(n_samples):
            t = float(i) / samplerate
            sample = amplitude * math.sin(2.0 * math.pi * freq * t)
            wf.writeframes(struct.pack('<h', int(sample)))

def _check_bluealsa_device(address):
    """Vérifie si BlueALSA détecte l'appareil comme périphérique audio."""
    try:
        formatted_addr = address.replace(':', '_').lower()
        cmd = f"bluealsa-aplay --list-devices 2>/dev/null | grep {formatted_addr} || true"
        ok, out = _run_cmd(cmd, shell=True, timeout=5)
        return ok and out.strip() != ''
    except Exception as e:
        app.logger.warning(f"Erreur _check_bluealsa_device: {e}")
        return False

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
            'is_ble': False,
            'audio_ready': False  # Nouveau: si BlueALSA voit l'appareil
        }

        # Extraire le nom, la classe
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
            elif 'UUID:' in line and '(' in line and ')' in line:
                uuid = line.split('(')[1].split(')')[0].strip().lower()
                if any(ble_uuid in uuid for ble_uuid in ['fe95', 'fdab', 'fef3', 'a201']):
                    details['is_ble'] = True
                    if details['icon'] == 'mdi:bluetooth':
                        details['icon'] = 'mdi:watch' if 'watch' in details['name'].lower() else 'mdi:bluetooth'

        # Vérifier si BlueALSA voit l'appareil (seulement si connecté)
        if details['connected']:
            details['audio_ready'] = _check_bluealsa_device(mac_address)
        
        return details
    except Exception as e:
        app.logger.error(f"Erreur get_device_details pour {mac_address}: {e}")
        return None

# ========== ENDPOINTS API ==========
@app.route('/api/status', methods=['GET'])
def get_status():
    """Endpoint de test pour vérifier que le serveur fonctionne."""
    return jsonify({
        'status': 'ok', 
        'service': 'Bluetooth Audio Gateway (BlueALSA)',
        'backend': 'BlueALSA'
    })

@app.route('/api/devices', methods=['GET'])
def get_devices():
    """Lister les appareils Bluetooth avec leur état."""
    try:
        # Obtenir la liste brute des appareils connus
        list_result = subprocess.run(['bluetoothctl', 'devices'], 
                                   capture_output=True, text=True)
        
        devices = []
        
        for line in list_result.stdout.split('\n'):
            if line.strip():
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    mac_address = parts[1]
                    details = get_device_details(mac_address)
                    if details:
                        devices.append(details)

        # Trier : appareils connectés en premier
        devices.sort(key=lambda x: (x['connected'], x['audio_ready']), reverse=True)

        return jsonify({'success': True, 'devices': devices})

    except Exception as e:
        app.logger.error(f"Erreur lors du scan: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/connect', methods=['POST'])
def connect_device():
    """Connecter à un appareil Bluetooth et vérifier la disponibilité audio."""
    try:
        data = request.get_json()
        address = data.get('address')
        app.logger.info(f"Connexion à: {address}")

        if not address:
            return jsonify({'success': False, 'error': 'Adresse MAC requise'}), 400

        # 1. Vérifier l'état actuel
        info_cmd = f"echo 'info {address}' | bluetoothctl"
        info_result = subprocess.run(info_cmd, shell=True, 
                                   capture_output=True, text=True, timeout=5)
        info_output = info_result.stdout

        paired = 'Paired: yes' in info_output
        trusted = 'Trusted: yes' in info_output

        # 2. Corriger état incohérent
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

        # 4. Connexion avec vérification BlueALSA
        app.logger.info(f"Tentative de connexion...")
        connect_cmd = f"echo -e 'connect {address}\\n' | timeout 15 bluetoothctl"
        result = subprocess.run(connect_cmd, shell=True, 
                              capture_output=True, text=True, timeout=20)
        
        time.sleep(3)  # Laisser le temps au profil audio de s'établir

        # 5. Vérification finale
        final_info_cmd = f"echo 'info {address}' | bluetoothctl"
        final_info_result = subprocess.run(final_info_cmd, shell=True, 
                                         capture_output=True, text=True, timeout=5)
        final_output = final_info_result.stdout

        if 'Connected: yes' in final_output:
            # Vérifier si BlueALSA voit l'appareil
            audio_ready = _check_bluealsa_device(address)
            
            if audio_ready:
                app.logger.info(f"✅ SUCCÈS : {address} connecté ET visible comme périphérique audio.")
                return jsonify({
                    'success': True, 
                    'message': 'Appareil connecté et prêt pour l\'audio.',
                    'audio_ready': True
                })
            else:
                app.logger.warning(f"⚠️  Connecté mais audio non détecté par BlueALSA.")
                return jsonify({
                    'success': True,
                    'message': 'Appareil connecté en Bluetooth, mais profil audio non encore actif.',
                    'audio_ready': False,
                    'warning': 'Le son peut ne pas fonctionner immédiatement. Réessayez dans 5-10 secondes.'
                })
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

@app.route('/api/play_test_sound', methods=['POST'])
def play_test_sound():
    """Joue un son de test via BlueALSA."""
    tmp_path = None
    try:
        data = request.get_json() or {}
        address = data.get('address')
        app.logger.info(f"Test audio BlueALSA pour {address}")

        # 1. Vérifier que l'appareil est connecté ET vu par BlueALSA
        if not _check_bluealsa_device(address):
            return jsonify({
                'success': False, 
                'error': 'Appareil non détecté par BlueALSA. Connectez-le d\'abord via /api/connect et attendez quelques secondes.'
            }), 400

        # 2. Générer un fichier WAV simple
        tmpf = tempfile.NamedTemporaryFile(delete=False, suffix='.wav')
        tmp_path = tmpf.name
        tmpf.close()
        _generate_tone_wav(tmp_path, duration=1.5, freq=660.0, volume=0.4)
        app.logger.info(f"Fichier de test généré: {tmp_path}")

        # 3. Jouer avec bluealsa-aplay
        app.logger.info("Lecture via bluealsa-aplay...")
        cmd = ['bluealsa-aplay', '--profile-a2dp', address, tmp_path]
        ok, out = _run_cmd(cmd, timeout=10)
        
        if ok:
            app.logger.info("✅ Son joué avec BlueALSA")
            return jsonify({
                'success': True, 
                'method': 'bluealsa-aplay',
                'message': 'Test audio envoyé avec succès.'
            })
        else:
            app.logger.error(f"Échec bluealsa-aplay: {out}")
            return jsonify({
                'success': False,
                'error': 'Échec de la lecture via BlueALSA.',
                'details': out[:200]
            }), 500

    except Exception as e:
        app.logger.error(f"Erreur play_test_sound: {e}", exc_info=True)
        return jsonify({'success': False, 'error': str(e)}), 500
    
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except:
                pass

@app.route('/api/audio_tools', methods=['GET'])
def audio_tools():
    """Retourne quels utilitaires audio sont disponibles."""
    try:
        tools = ['bluealsa-aplay', 'bluealsa', 'aplay', 'bluetoothctl']
        found = {t: _which(t) for t in tools}

        # Vérifier si BlueALSA daemon est en cours d'exécution
        bluealsa_running = False
        bluealsa_info = "Not running"
        if found.get('bluealsa'):
            ps_ok, ps_out = _run_cmd(['pgrep', '-f', 'bluealsa'], timeout=5)
            if ps_ok:
                bluealsa_running = True
                bluealsa_info = "Running (PID: " + ps_out.strip().replace('\n', ', ') + ")"
            else:
                bluealsa_info = "Not found in process list"

        # Liste des appareils BlueALSA
        bluealsa_devices = ""
        if found.get('bluealsa-aplay'):
            ok, out = _run_cmd(['bluealsa-aplay', '--list-devices'], timeout=5)
            if ok:
                bluealsa_devices = out[:500]

        return jsonify({
            'success': True, 
            'tools': found, 
            'bluealsa_daemon': {
                'running': bluealsa_running, 
                'info': bluealsa_info
            },
            'bluealsa_devices': bluealsa_devices
        })
    except Exception as e:
        app.logger.error(f"Erreur audio_tools: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

# ========== DÉMARRAGE ==========
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False, threaded=True)