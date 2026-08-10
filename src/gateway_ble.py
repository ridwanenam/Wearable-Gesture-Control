import asyncio
import requests
import json
import time
from bleak import BleakScanner, BleakClient

# ==================== CONFIGURATION ====================
API_KEY = "ei_5397659a4bb90f94c93211022df90b6f8ea1edcbaf8afbd8"
INGESTION_URL = "https://ingestion.edgeimpulse.com/api/training/data"
TARGET_NAME = "Smartwatch-PUI"

# PERBAIKAN: Karakteristik TX UUID harus sama persis dengan kode Arduino
CHARACTERISTIC_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

# STRATEGI AKUISISI DATA: 
# Ganti manual sesuai sesi rekaman yang ingin Anda kumpulkan ke Edge Impulse
# Pilihan label mentah: "IDLE", "TAP", atau "FIST"
LABEL_TARGET = "IDLE" 

# PERBAIKAN: Naikkan durasi agar Anda punya waktu melakukan variasi gerakan mikro
SAMPLING_DURATION_SEC = 20.0 

# PERBAIKAN SINKRONISASI HARDWARE: Dikunci mutlak pada 104 Hz bawaan Arduino LSM6DSOX
HARDWARE_SAMPLING_RATE_HZ = 104.0
LOCKED_INTERVAL_MS = 1000.0 / HARDWARE_SAMPLING_RATE_HZ # ~9.615 ms
# =======================================================

raw_buffer = []

def notification_handler(sender, data):
    global raw_buffer
    try:
        # Decode data string "x,y,z\n" dari paket BLE Notify Arduino
        payload = data.decode('utf-8').strip()
        if payload:
            # Memisahkan string berdasarkan tanda koma menjadi float m/s2
            x, y, z = map(float, payload.split(','))
            raw_buffer.append([x, y, z])
    except Exception as e:
        # Mengabaikan paket data yang terpotong di tengah jalan saat pengiriman cepat
        pass

async def main():
    global raw_buffer
    raw_buffer.clear()
    
    print(f" Menguji koneksi internet ke Edge Impulse Ingestion API...")
    try:
        requests.get("https://edgeimpulse.com", timeout=3)
    except Exception:
        print("❌ ERROR: Laptop tidak terhubung ke Internet! Periksa Wi-Fi Anda.")
        return

    print(f"📡 Mencari perangkat BLE dengan nama '{TARGET_NAME}'...")
    devices = await BleakScanner.discover()
    target_device = None
    
    for d in devices:
        if d.name == TARGET_NAME:
            target_device = d
            break
            
    if not target_device:
        print(f"❌ Perangkat '{TARGET_NAME}' tidak ditemukan. Pastikan Arduino menyala via baterai.")
        return
        
    print(f"✅ Perangkat ditemukan! MAC/Address: {target_device.address}")
    print(f"🔗 Menghubungkan secara wireless...")
    
    async with BleakClient(target_device.address) as client:
        print(f" Connected! Mengaktifkan deskriptor notifikasi...")
        await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
        
        print("\n" + "="*50)
        print(f"🚀 SILAKAN LAKUKAN GERAKAN MIKRO-GESTUR [{LABEL_TARGET}] BERULANG-ULANG!")
        print(f"⏳ Perekaman sedang berjalan secara nirkabel selama {SAMPLING_DURATION_SEC} detik...")
        print("="*50 + "\n")
        
        # Laptop mendengarkan aliran data akselerometer dari smartwatch bertenaga baterai Anda
        await asyncio.sleep(SAMPLING_DURATION_SEC) 
        
        await client.stop_notify(CHARACTERISTIC_UUID)
        print(" Perekaman selesai. Memutus koneksi Bluetooth...")

    total_readings = len(raw_buffer)
    if total_readings == 0:
        print("❌ Gagal mengumpulkan data. Buffer kosong, periksa pengiriman Arduino.")
        return
        
    # Menghitung efisiensi sampling aktual vs target hardware untuk pemantauan kualitas data
    expected_readings = int(SAMPLING_DURATION_SEC * HARDWARE_SAMPLING_RATE_HZ)
    efficiency = (total_readings / expected_readings) * 100
    print(f"📊 Terkumpul {total_readings}/{expected_readings} data points (Efisiensi Transmisi BLE: {efficiency:.1f}%).")

    # Membuat nama berkas unik menggunakan timestamp unix
    file_name = f"{LABEL_TARGET}_{int(time.time())}.json"

    headers = {
        "x-api-key": API_KEY,
        "x-file-name": file_name,       
        "x-label": LABEL_TARGET,         
        "Content-Type": "application/json"
    }
    
    # Bungkus data ke format JSON resmi Edge Impulse Ingestion API
    payload_json = {
        "protected": {
            "ver": "v1",
            "alg": "none",
            "sensor_name": "accelerometer"
        },
        "signature": "0000000000000000000000000000000000000000000000000000000000000000",
        "payload": {
            "device_name": "Smartwatch-PUI",
            "device_type": "RP2040_BLE",
            "interval_ms": LOCKED_INTERVAL_MS, # Mengunci interval pada ketetapan hardware 104 Hz
            "sensors": [
                {"name": "accX", "units": "m/s2"},
                {"name": "accY", "units": "m/s2"},
                {"name": "accZ", "units": "m/s2"}
            ],
            "values": raw_buffer
        }
    }
    
    print(f"☁️  Mengunggah sampel nirkabel ke Edge Impulse Studio dengan label '{LABEL_TARGET}'...")
    response = requests.post(INGESTION_URL, headers=headers, json=payload_json)
    
    if response.status_code == 200:
        print(f"🎉 SUKSES! File '{file_name}' otomatis masuk ke Dashboard Data Acquisition Anda.")
    else:
        print(f"❌ Gagal Upload. Kode Error: {response.status_code}, Detail: {response.text}")

if __name__ == "__main__":
    asyncio.run(main())
