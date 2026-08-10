import asyncio
from bleak import BleakScanner, BleakClient

# ==================== CONFIGURATION ====================
TARGET_NAME = "Wearable_Gesture_Controller"
CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8" 
# =======================================================

def notification_handler(sender, data):
    try:
        # Decode data string bersih dari Smartwatch
        payload = data.decode('utf-8').strip()
        
        if payload and payload != "IDLE":
            # Mencetak setiap pemicu aksi yang berhasil ditembak via BLE
            print("\n" + "="*50)
            print(f"📡 [WIRELESS DETECTED] -> {payload}")
            
            # Memberikan keterangan kontekstual untuk memperjelas visualisasi
            if "TAP" in payload:
                print("📊 Metode Deteksi     : Gaya Transien Mekanis (Force)")
            elif "FIST" in payload:
                print("📊 Metode Deteksi     : Mikro-Tilting Cerdas (Relative Roll)")
                print(f"💡 Info Gerakan       : {'Miring Kiri' if payload == 'NEXT_FIST' else 'Miring Kanan'}")
                
            print("="*50)
    except Exception as e:
        pass

async def main():
    print(f"🔍 Mencari Smartwatch dengan nama '{TARGET_NAME}'...")
    devices = await BleakScanner.discover()
    target_device = None
    
    for d in devices:
        if d.name == TARGET_NAME:
            target_device = d
            break
            
    if not target_device:
        print(f"❌ Smartwatch '{TARGET_NAME}' tidak ditemukan! Pastikan sakelar baterai sudah ON.")
        return
        
    print(f"✅ Perangkat Ditemukan! MAC Address: {target_device.address}")
    print(f"🔗 Menghubungkan monitor nirkabel secara nirkabel...")
    
    async with BleakClient(target_device.address) as client:
        print(f"🚀 MONITOR AKTIF! Silakan lakukan mikro-gestur pada jam tangan Anda.")
        print(f"📝 Seluruh log pengiriman string BLE akan dicetak di bawah ini:\n")
        
        await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
        
        # Loop abadi agar skrip terus berjalan memantau log debug
        while True:
            await asyncio.sleep(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n⏹️ Monitor Nirkabel Dimatikan.")
