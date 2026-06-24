"""
reader.py — Lector de datos VectorNav vía WebSocket
Se conecta al simulador (o a un bridge del sensor real) y parsea los mensajes.
Uso: python reader.py
"""

import asyncio
import websockets
import json
import time

WS_URI = "ws://localhost:8765"


def parse_vnins(line: str) -> dict | None:
    """
    Parsea una sentencia $VNINS del VectorNav.
    Formato:
    $VNINS,Time,Week,Status,Yaw,Pitch,Roll,Lat,Lon,Alt,VN,VE,VD,AttUnc,PosUnc,VelUnc*CS
    """
    try:
        parts = line.strip().split(',')
        if parts[0] != '$VNINS' or len(parts) < 16:
            return None

        vel_uncertainty_str = parts[15].split('*')[0]

        return {
            "tipo_mensaje": parts[0],
            "tiempo_gps":   float(parts[1]),
            "semana_gps":   int(parts[2]),
            "estado":       parts[3],
            "orientacion": {
                "yaw_grados":   float(parts[4]),
                "pitch_grados": float(parts[5]),
                "roll_grados":  float(parts[6]),
            },
            "posicion": {
                "latitud":         float(parts[7]),
                "longitud":        float(parts[8]),
                "altitud_metros":  float(parts[9]),
            },
            "velocidad": {
                "norte_m_s": float(parts[10]),
                "este_m_s":  float(parts[11]),
                "abajo_m_s": float(parts[12]),
            },
            "incertidumbre": {
                "actitud":   float(parts[13]),
                "posicion":  float(parts[14]),
                "velocidad": float(vel_uncertainty_str),
            },
        }
    except Exception:
        return None


async def leer():
    print(f"Conectando a {WS_URI} ...\n")
    async with websockets.connect(WS_URI) as ws:
        print("Conexión establecida. Esperando datos...\n")
        async for mensaje in ws:
            if mensaje == "__FIN__":
                print("\n── Simulación finalizada ──")
                break

            datos = parse_vnins(mensaje)
            if datos:
                print(f"[{time.strftime('%H:%M:%S')}] Datos recibidos:")
                print(json.dumps(datos, indent=4, ensure_ascii=False))
                print("-" * 40)


if __name__ == "__main__":
    asyncio.run(leer())
