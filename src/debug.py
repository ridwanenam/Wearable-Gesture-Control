import asyncio
import sys
from bleak import BleakScanner, BleakClient

# ==================== CONFIGURATION ====================
TARGET_NAME = "Wearable_Gesture_Controller"
CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8" 
# =======================================================

def notification_handler(sender, data):
    """Fungsi callback yang otomatis dipicu setiap kali Arduino mengirim data lewat BLE"""
    try:
        decoded_string = data.decode("utf-8").strip()
        
        if decoded_string.startswith("F:"):
            # Parsing data mentah: "F:1.45,D:-0.20"
            parts = decoded_string.split(",")
            force_val = parts[0].replace("F:", "")
            deltay_val = parts[1].replace("D:", "")
            
            # Trik Overwrite: Menggunakan \r di awal dan end="" agar teks berubah di tempat (tidak baris baru)
            sys.stdout.write(f"\r📊 [LIVE SENSOR] Force: {force_val.ljust(5)} | Delta Y: {deltay_val.ljust(6)}")
            sys.stdout.flush()
            
        else:
            # Bersihkan baris live sensor terlebih dahulu sebelum mencetak trigger utama
            sys.stdout.write("\r" + " " * 70 + "\r") 
            
            # Cetak hasil akhir gestur yang valid dengan mencolok
            print("=" * 60)
            print(f"🚀 [GESTURE TRIGGERED] -> {decoded_string} !!!")
            print("=" * 60)
            
    except Exception as e:
        pass # Mengabaikan error split jika ada paket BLE yang korup di udara

async def main():
    print(f"🔎 Mencari perangkat dengan nama lokal: '{TARGET_NAME}'...")
    device = await BleakScanner.find_device_by_name(TARGET_NAME)
    
    if not device:
        print(f"❌ Perangkat '{TARGET_NAME}' tidak ditemukan. Pastikan Arduino menyala!")
        return

    print(f"✅ Perangkat ditemukan! [{device.address}]")
    print(f"🔗 Hubungkan koneksi nirkabel...")
    
    async with BleakClient(device.address) as client:
        if client.is_connected:
            print(f"🎉 Terhubung sukses!")
            print("📈 Memulai pemantauan sensor (Terminal Auto-Clean Active).\n")
            
            await client.start_notify(CHARACTERISTIC_UUID, notification_handler)
            
            while True:
                await asyncio.sleep(1)
        else:
            print("❌ Gagal menjalin koneksi nirkabel.")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Pemantauan dihentikan.")
