# Proyecto ROVER
Simulación Inteligente y Control Remoto de Robots Terrestres


## Description
ROVER es un ecosistema de simulación avanzado desarrollado en Godot 4.6.3. Su objetivo es proporcionar un entorno virtual para la gestión de robots terrestres, permitiendo tanto el control manual remoto como la navegación autónoma mediante la interpretación de datos del terreno (mapeo de costos).


## Arquitectura
El sistema utiliza un protocolo JSON sobre sockets (TCP/UDP) para garantizar la interoperabilidad entre el hardware físico (ESP) y el entorno de Godot:

Data Structure: JSON plano para telemetría (GPS, IMU, Estado de sensores).

Mapeo del Mundo: Archivos de configuración (JSON/TSCN) que definen la grilla de navegación, incluyendo valores de "costo de terreno" para optimización de rutas.


## Roadmap

Fase Alpha: Control y Telemetría Básica

Conexión socket (IP/Puerto) entre ESP y Godot.

Visualización del Rover en entorno virtual.

Movimiento básico (sin colisiones).

Fase Beta: Navegación Inteligente

Implementación de grilla de costos (Pathfinding basado en dificultad de terreno).

Algoritmo para calcular rutas óptimas de punto A a punto B.

Fase Gamma: Interacción Dinámica

Detección de obstáculos en tiempo real (visión artificial).

Lógica de espera y re-cálculo de path tras superación de umbrales de tiempo.

Fase Delta: Pulido y Productización

Interfaz de usuario (UI/UX) profesional.

Post-procesado visual para presentación a equipo de marketing.
## Requisitos de Entorno

📋 Requisitos de Entorno
Motor: Godot Engine v4.6.3.

Firmware: C++ (Arduino Framework/ESP-IDF) para ESP.

Protocolo: Comunicación vía Socket con serialización JSON.

## Notas sobre la implementación

Navegación: Se recomienda utilizar el sistema de NavigationServer3D de Godot junto con una grilla de pesos (NavigationRegion) para gestionar las áreas de "difícil paso".

Serialización: El flujo de trabajo recomendado es enviar el JSON desde el ESP, capturarlo en Godot mediante PacketPeer y procesarlo como Dictionary.

Un consejo técnico para tu "Fase Beta":
Cuando implementes los "lugares más difíciles de pasar", no intentes hacer el pathfinding manualmente desde cero. Godot tiene un nodo llamado NavigationRegion3D que permite configurar "Navigation Layers" y "Region Layers".

Puedes asignar un costo más alto a ciertas áreas de la grilla (por ejemplo, lodo o arena).

El motor de Godot calculará automáticamente el camino más rápido basado en esos "pesos" o costos. Esto te ahorrará meses de programación matemática compleja.
## Authors

- [Julian Aguirre](https://www.github.com/juliMAB)
- [Diego Agustin Chanique] (https://github.com/bondrewd0)
