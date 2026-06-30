"""
simulator.py — Simulador de sensor VectorNav ($VNINS)
Genera datos falsos de navegación y los transmite por WebSocket.
Uso: python simulator.py
"""

import asyncio
import websockets
import math
import time
import json
import random

# ─── CONFIGURACIÓN ────────────────────────────────────────────────────────────
WS_HOST = "localhost"
WS_PORT = 8765
UPDATE_HZ = 10          # cuántas veces por segundo se envía un dato
# ──────────────────────────────────────────────────────────────────────────────


def calcular_checksum(sentence: str) -> str:
    """Calcula el checksum XOR NMEA (sin el $ y sin el *)."""
    checksum = 0
    for char in sentence:
        checksum ^= ord(char)
    return f"{checksum:02X}"


def construir_vnins(t: float, pos: dict, vel: dict, att: dict) -> str:
    """Arma la cadena $VNINS con el formato correcto."""
    gps_time = t % 604800          # segundos dentro de la semana GPS
    gps_week = 2300                # semana GPS fija (no importa para el simulador)
    status   = "8005"              # estado OK típico del VectorNav

    fields = [
        "VNINS",
        f"{gps_time:.4f}",
        str(gps_week),
        status,
        f"{att['yaw']:.6f}",
        f"{att['pitch']:.6f}",
        f"{att['roll']:.6f}",
        f"{pos['lat']:.8f}",
        f"{pos['lon']:.8f}",
        f"{pos['alt']:.4f}",
        f"{vel['norte']:.6f}",
        f"{vel['este']:.6f}",
        f"{vel['abajo']:.6f}",
        "0.050000",                # incertidumbre actitud  (baja = sensor sano)
        "1.200000",                # incertidumbre posición
        f"0.250000",               # incertidumbre velocidad
    ]

    body     = ",".join(fields)
    checksum = calcular_checksum(body)
    return f"${body}*{checksum}"


# ─── SECUENCIAS DE MOVIMIENTO ─────────────────────────────────────────────────
# Cada función recibe el tiempo relativo `t` (segundos desde el inicio de la
# secuencia) y devuelve (pos_delta_lat, pos_delta_lon, vel, att).

def secuencia_avance_recto(t: float, estado: dict):
    """Avanza hacia el Norte a ~10 m/s durante toda la secuencia."""
    velocidad = 10.0   # m/s
    # 1 grado lat ≈ 111_111 m
    estado["lat"] += velocidad / 111_111 / UPDATE_HZ
    return {
        "vel": {"norte": velocidad, "este": 0.0, "abajo": 0.0},
        "att": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0},
    }


def secuencia_curva_derecha(t: float, estado: dict):
    """Describe una curva hacia la derecha (Este) durante ~30 s."""
    velocidad = 10.0
    yaw = min(t * 3.0, 90.0)              # rota hasta 90° en 30 s
    yaw_rad = math.radians(yaw)
    vn = velocidad * math.cos(yaw_rad)
    ve = velocidad * math.sin(yaw_rad)
    estado["lat"] += vn / 111_111 / UPDATE_HZ
    estado["lon"] += ve / 111_111 / UPDATE_HZ
    return {
        "vel": {"norte": vn, "este": ve, "abajo": 0.0},
        "att": {"yaw": yaw, "pitch": 0.0, "roll": min(t * 1.0, 8.0)},
    }


def secuencia_subida(t: float, estado: dict):
    """Sube una rampa: pitch positivo y velocidad vertical negativa (sube)."""
    velocidad = 8.0
    pitch = min(t * 2.0, 15.0)           # hasta 15° de inclinación
    estado["lat"] += velocidad / 111_111 / UPDATE_HZ
    estado["alt"] += 0.5 / UPDATE_HZ     # sube 0.5 m/s
    return {
        "vel": {"norte": velocidad, "este": 0.0, "abajo": -0.5},
        "att": {"yaw": 0.0, "pitch": pitch, "roll": 0.0},
    }


def secuencia_detenido(t: float, estado: dict):
    """Vehículo quieto con pequeño ruido de sensor."""
    return {
        "vel": {
            "norte": random.uniform(-0.05, 0.05),
            "este":  random.uniform(-0.05, 0.05),
            "abajo": random.uniform(-0.02, 0.02),
        },
        "att": {
            "yaw":   random.uniform(-0.1, 0.1),
            "pitch": random.uniform(-0.1, 0.1),
            "roll":  random.uniform(-0.1, 0.1),
        },
    }


def secuencia_vuelta_completa(t: float, estado: dict):
    """Da una vuelta completa (360°) en 60 s girando sobre sí mismo."""
    velocidad = 5.0
    yaw = (t * 6.0) % 360.0              # 360° en 60 s
    yaw_rad = math.radians(yaw)
    vn = velocidad * math.cos(yaw_rad)
    ve = velocidad * math.sin(yaw_rad)
    estado["lat"] += vn / 111_111 / UPDATE_HZ
    estado["lon"] += ve / 111_111 / UPDATE_HZ
    return {
        "vel": {"norte": vn, "este": ve, "abajo": 0.0},
        "att": {"yaw": yaw, "pitch": 0.0, "roll": 0.0},
    }


# ─── PLAYLIST DE SECUENCIAS ───────────────────────────────────────────────────
# Lista de (nombre, función, duración_en_segundos)
PLAYLIST = [
    ("Detenido inicial",    secuencia_detenido,       5),
    ("Avance recto",        secuencia_avance_recto,  10),
    ("Curva a la derecha",  secuencia_curva_derecha, 15),
    ("Avance recto",        secuencia_avance_recto,  10),
    ("Subida en rampa",     secuencia_subida,        10),
    ("Vuelta completa",     secuencia_vuelta_completa, 20),
    ("Detenido final",      secuencia_detenido,       5),
]
# ──────────────────────────────────────────────────────────────────────────────


async def generador(websocket):
    """Corre la playlist y envía cada trama al cliente WebSocket conectado."""
    addr = websocket.remote_address
    print(f"  Cliente conectado: {addr}")

    # Estado mutable del vehículo (posición acumulada)
    estado = {
        "lat": -34.570000,   # Buenos Aires como punto de partida
        "lon": -58.430000,
        "alt": 25.0,
    }

    t_inicio_global = time.time()

    try:
        for nombre, fn, duracion in PLAYLIST:
            print(f"\n[Secuencia] '{nombre}' ({duracion} s)")
            t_ini = time.time()
            paso  = 1.0 / UPDATE_HZ

            while True:
                t_rel = time.time() - t_ini
                if t_rel >= duracion:
                    break

                resultado = fn(t_rel, estado)
                trama = construir_vnins(
                    t   = time.time() - t_inicio_global,
                    pos = estado,
                    vel = resultado["vel"],
                    att = resultado["att"],
                )

                await websocket.send(trama)
                await asyncio.sleep(paso)

        print("\n[Playlist] Playlist completada.")
        await websocket.send("__FIN__")

    except websockets.exceptions.ConnectionClosed:
        print(f"  Cliente {addr} desconectado.")


async def main():
    print(f"[Simulador] VectorNav corriendo en ws://{WS_HOST}:{WS_PORT}")
    print(f"   Frecuencia: {UPDATE_HZ} Hz  |  Secuencias: {len(PLAYLIST)}\n")
    async with websockets.serve(generador, WS_HOST, WS_PORT):
        await asyncio.Future()   # corre indefinidamente


if __name__ == "__main__":
    asyncio.run(main())
