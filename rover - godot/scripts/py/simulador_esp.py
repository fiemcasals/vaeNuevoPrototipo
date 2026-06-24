import asyncio
import websockets

async def servidor(websocket):
    print(f"¡Godot se ha conectado!")
    try:
        async for mensaje in websocket:
            print(f"Recibido desde Godot: {mensaje}")
            if mensaje == "ENCENDER":
                print("[SIMULACIÓN] 💡 LED VIRTUAL ENCENDIDO")
                await websocket.send("LED Encendido (Simulado)")
            elif mensaje == "1":
                await websocket.send("-1")
            else:
                await websocket.send(f"Comando '{mensaje}' recibido correctamente")
                
    # Capturamos tanto la desconexión limpia como la abrupta (Error o Timeout)
    except (websockets.exceptions.ConnectionClosedOK, websockets.exceptions.ConnectionClosedError):
        print("Aviso: Godot se ha desconectado abruptamente (Timeout/Corte de red).")
    except Exception as e:
        print(f"Ocurrió un error inesperado: {e}")
    finally:
        print("Limpiando recursos de la conexión actual. Listo para el siguiente intento.\n")

async def main():
    async with websockets.serve(servidor, "0.0.0.0", 81):
        print("Servidor ESP simulado listo y escuchando en el puerto 81...")
        await asyncio.Future()

asyncio.run(main())