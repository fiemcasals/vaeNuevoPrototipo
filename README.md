# Simulador Integrado: Control Autónomo y Estaciones de Operación (Godot + Node.js)

Este proyecto consiste en la fusión del simulador 3D desarrollado en **Godot** (`rover - godot`) y el cerebro de lógica/navegación desarrollado en **React/Node.js** (`PPS-VAE`).

El sistema está dividido en dos subsistemas principales que se comunican en tiempo real mediante **WebSockets**:
1. **Servidor de Lógica (Node.js)**: Calcula las rutas óptimas mediante Hybrid A* y procesa el seguimiento Pure Pursuit (autopiloto).
2. **Ambiente y Estaciones de Operación (Godot)**: Simula la física del vehículo (`VehicleBody3D`), renderiza el ambiente 3D y ofrece la interfaz de usuario para el conductor y el artillero.

---

## 📋 Requisitos Previos

- **Node.js** (versión 18 o superior recomendada).
- **Godot Engine 4.x** (probado y configurado en Godot 4.2+).

---

## 🚀 Instrucciones de Inicio rápido

Para levantar la simulación completa, sigue estos dos pasos sencillos:

### Paso 1: Iniciar el Servidor de Lógica (Node.js)

Abre una terminal de comandos, navega al directorio `PPS-VAE` e inicia el servidor:

```bash
# Navegar al directorio de lógica
cd PPS-VAE

# Instalar dependencias (solo la primera vez)
npm install

# Iniciar el servidor
node pps_logic_server.js
```

*Verás el siguiente mensaje de confirmación:*  
`[PPS-VAE Logic Server] Running on ws://localhost:8767`

---

### Paso 2: Iniciar la Simulación (Godot)

Puedes iniciar la simulación por comandos o mediante el editor gráfico:

#### Opción A: Por comandos (Recomendado y más rápido)
Abre otra consola de comandos en la carpeta raíz del proyecto (`vaeNuevoPrototipo`) y ejecuta:

```bash
# Si estás en la carpeta raíz 'vaeNuevoPrototipo':
godot --path "rover - godot"
```

Si ya entraste a la subcarpeta `rover - godot` usando `cd "rover - godot"`, simplemente ejecuta:

```bash
# Si estás dentro de la carpeta 'rover - godot' (donde está el archivo project.godot):
godot
```
*(Nota: Si usas PowerShell, escribe `godot.exe` o `godot.exe --path .` asegurándote de estar dentro de la carpeta `rover - godot` para evitar que se abra el selector de proyectos vacío).*

---

#### Opción B: Desde la interfaz de Godot
1. Abre **Godot Engine 4**.
2. En el gestor de proyectos, haz clic en **Importar** (Import), busca y selecciona la carpeta `rover - godot` (específicamente el archivo `project.godot`).
3. Haz clic en **Importar y Editar**.
4. Una vez en el editor, haz clic en el botón de **Play** (esquina superior derecha) o presiona **F5**.

---

## 🎮 Modos de Operación

Al iniciar la simulación, se te presentará una interfaz para elegir tu rol/estación:

### 1. Conducción (Estación del Piloto) 🚗
* **Descripción**: Permite conducir el vehículo manualmente o activar el piloto automático.
* **Controles**:
  - **W/S**: Acelerar / Reversa.
  - **A/D**: Dirección (Giro izquierda / derecha).
  - **Espacio**: Freno de mano.
  - **Botón "Seleccionar Destino"**: Te permite elegir un punto de interés en el mapa para que el servidor de Node.js calcule la trayectoria (Hybrid A*) y el piloto automático dirija el vehículo hasta el destino.

### 2. Armamento (Estación del Artillero) 🔫
* **Descripción**: Bloquea los controles de tracción y te permite apuntar manualmente la torreta y la cámara en primera persona del arma de apoyo.
* **Controles**:
  - **A/D** (o **Flechas izquierda/derecha**): Rotación horizontal (**Azimut** de 0° a 360°).
  - **W/S** (o **Flechas arriba/abajo**): Rotación vertical (**Elevación** limitada entre -23° y 45°).
  - **Mouse (Click presionado y arrastrar)**: Apuntado libre y suave.
  - **Tecla Escape** o botón **Volver**: Regresa al menú selector de modalidad.

---

## 🔧 Solución de Problemas Comunes

### Error: `listen EADDRINUSE: address already in use :::8767`
Este error significa que el puerto `8767` ya está siendo utilizado por otro proceso en tu computadora (probablemente una instancia anterior del servidor que no se cerró correctamente).

**Solución en Windows (PowerShell):**
1. Busca el ID del proceso que usa el puerto:
   ```powershell
   Get-NetTCPConnection -LocalPort 8767
   ```
2. Cierra el proceso usando su PID (reemplaza `1234` con el PID obtenido del comando anterior):
   ```powershell
   Stop-Process -Id 1234 -Force
   ```
3. Vuelve a iniciar el servidor (`node pps_logic_server.js`).

---
*Documento generado por Antigravity*
