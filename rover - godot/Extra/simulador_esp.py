import asyncio
import websockets

async def servidor(websocket):
    print(f"¡Godot se ha conectado desde el teléfono!")
    try:
        async for mensaje in websocket:
            print(f"Recibido desde Godot: {mensaje}")
            
            if mensaje == "ENCENDER":
                print("[SIMULACIÓN] 💡 LED VIRTUAL ENCENDIDO")
                await websocket.send("LED Encendido (Simulado)")
            else:
                await websocket.send(f"Comando '{mensaje}' recibido correctamente")
                
    except websockets.exceptions.ConnectionClosedOK:
        print("Godot se ha desconectado.")

async def main():
    # Escucha en todas las interfaces (0.0.0.0) en el puerto 81
    async with websockets.serve(servidor, "0.0.0.0", 81):
        print("Servidor ESP simulado listo y escuchando en el puerto 81...")
        await asyncio.Future() # Mantiene el servidor corriendo

asyncio.run(main())