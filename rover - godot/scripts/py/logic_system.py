"""
logic_system.py — Logic Subsystem (Brain)
Hosts a WebSocket server to receive vehicle environment/telemetry data,
runs the path tracking control algorithms, and broadcasts movement commands (orders)
to both Godot and the physical vehicle (ESP32).

Uso: python logic_system.py
"""

import asyncio
import json
import math
import websockets

# CONFIGURATION
WS_HOST = "0.0.0.0"
WS_PORT = 8767

# Grid data received from Godot via init_level
_level_tiles = []
_level_spacing = 4.0

WEIGHTS = {
    "no_caminable": 999999,
    "obstaculo": 999999,
    "caminable": 1,
    "spawn_point": 1,
    "punto_interes": 1,
    "objetivo": 1,
    "peso_3_4": 3,
}
ALIASES = {
    "negro": "no_caminable", "blocked": "no_caminable",
    "gris": "peso_3_4", "gray": "peso_3_4",
    "blanco": "caminable", "walkable": "caminable",
    "verde": "spawn_point", "spawnpoint": "spawn_point",
    "amarillo": "punto_interes", "interest_point": "punto_interes", "interest": "punto_interes",
    "naranja": "obstaculo", "obstacle": "obstaculo",
    "violeta": "objetivo", "target": "objetivo",
}


def _get_weight(tile_type):
    canonical = ALIASES.get(tile_type, tile_type)
    return WEIGHTS.get(canonical, 999999)


def _is_walkable(col, row):
    if not _level_tiles:
        return False
    if row < 0 or row >= len(_level_tiles) or col < 0 or col >= len(_level_tiles[0]):
        return False
    return _get_weight(_level_tiles[row][col]) < 999999


def a_star_pathfinding(start_col, start_row, goal_col, goal_row):
    if not _is_walkable(start_col, start_row) or not _is_walkable(goal_col, goal_row):
        return None

    start = (start_col, start_row)
    goal = (goal_col, goal_row)

    open_set = [start]
    came_from = {}
    g_score = {start: 0}
    f_score = {start: abs(start_col - goal_col) + abs(start_row - goal_row)}

    max_iterations = len(_level_tiles) * len(_level_tiles[0]) * 4

    while open_set and max_iterations > 0:
        max_iterations -= 1
        current = min(open_set, key=lambda cell: f_score.get(cell, float('inf')))

        if current == goal:
            path_grid = []
            node = goal
            while node in came_from:
                path_grid.insert(0, node)
                node = came_from[node]
            path_grid.insert(0, start)

            path_world = []
            for col, row in path_grid:
                path_world.append({
                    "x": col * _level_spacing,
                    "z": row * _level_spacing,
                    "direction": 1,
                })
            return path_world

        open_set.remove(current)

        for dcol, drow in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            neighbor = (current[0] + dcol, current[1] + drow)
            if not _is_walkable(neighbor[0], neighbor[1]):
                continue

            weight = _get_weight(_level_tiles[neighbor[1]][neighbor[0]])
            tentative_g = g_score[current] + weight

            if neighbor not in g_score or tentative_g < g_score[neighbor]:
                came_from[neighbor] = current
                g_score[neighbor] = tentative_g
                f_score[neighbor] = tentative_g + abs(neighbor[0] - goal_col) + abs(neighbor[1] - goal_row)
                if neighbor not in open_set:
                    open_set.append(neighbor)

    return None


class PathTracker:
    def __init__(self):
        self.path = []
        self.current_index = 0
        self.max_speed = 7.5       # Default maximum speed
        self.wheelbase = 2.0       # Distance between axles
        self.torque = 300.0        # Engine torque multiplier
        self._off_grid = False
        self._recovery_target = None
        self._stuck_frames = 0
        self._reversing = False
        self._reverse_frames = 0

    def _world_to_grid(self, x, z):
        col = round(x / _level_spacing)
        row = round(z / _level_spacing)
        return (col, row)

    def _is_walkable_cell(self, col, row):
        if not _level_tiles:
            return True
        if row < 0 or row >= len(_level_tiles) or col < 0 or col >= len(_level_tiles[0]):
            return False
        return _get_weight(_level_tiles[row][col]) < 999999

    def _find_nearest_walkable(self, x, z):
        if not _level_tiles:
            return (x, z)
        start_col, start_row = self._world_to_grid(x, z)
        if self._is_walkable_cell(start_col, start_row):
            return (x, z)

        visited = set()
        queue = [(start_col, start_row)]
        visited.add((start_col, start_row))
        max_radius = max(len(_level_tiles), len(_level_tiles[0])) * 2

        while queue:
            col, row = queue.pop(0)
            if self._is_walkable_cell(col, row):
                return (col * _level_spacing, row * _level_spacing)
            for dcol, drow in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
                nc, nr = col + dcol, row + drow
                if (nc, nr) not in visited and abs(nc - start_col) + abs(nr - start_row) <= max_radius:
                    visited.add((nc, nr))
                    queue.append((nc, nr))
        return (x, z)

    def set_path(self, path):
        self.path = path
        self.current_index = 0
        print(f"[Tracker] New path set with {len(path)} waypoints.")

    def stop(self):
        self.path = []
        self.current_index = 0
        print("[Tracker] Tracking stopped.")

    def _apply_anti_stuck(self, orders, speed):
        if orders["engine_force"] > 100 and abs(speed) < 0.3:
            self._stuck_frames += 1
        else:
            self._stuck_frames = max(0, self._stuck_frames - 2)

        if self._stuck_frames > 90:
            self._reversing = True
            self._reverse_frames = 75
            self._stuck_frames = 0
            print("[Tracker] Atascado! Marcha atras por 1.25s...")

        if self._reversing:
            self._reverse_frames -= 1
            if self._reverse_frames <= 0:
                self._reversing = False
                self._stuck_frames = 0
                print("[Tracker] Fin marcha atras.")
            else:
                orders["engine_force"] = -200.0
                orders["brake"] = 0.0
                orders["steering"] = 0.0
                orders["direction"] = -1
        return orders

    def update(self, x, z, yaw, speed, config_data=None, evasion_data=None):
        if config_data:
            self.max_speed = config_data.get("max_speed", self.max_speed)
            self.wheelbase = config_data.get("wheelbase", self.wheelbase)
            self.torque = config_data.get("torque", self.torque)

        # Priority: obstacle avoidance reverse
        if evasion_data:
            inner = evasion_data.get("inner_count", 0)
            retrocediendo = evasion_data.get("retrocediendo", False)
            nivel_zona = evasion_data.get("nivel_zona", 0)
            ev_lateral = evasion_data.get("lateral", 0.0)
            ev_brake = evasion_data.get("brake", 0.0)

            if retrocediendo and nivel_zona >= 3 and inner > 0:
                orders = {
                    "type": "orders",
                    "steering": -ev_lateral * 0.5,
                    "engine_force": -self.torque * 0.6,
                    "brake": 0.0,
                    "direction": -1,
                    "current_waypoint_index": self.current_index,
                    "target_point": {"x": x, "z": z}
                }
                return orders

        col, row = self._world_to_grid(x, z)
        if _level_tiles and not self._is_walkable_cell(col, row):
            self._off_grid = True
            rx, rz = self._find_nearest_walkable(x, z)
            self._recovery_target = (rx, rz)
            dx = rx - x
            dz = rz - z
            dist_to_recovery = math.hypot(dx, dz)

            local_z = dx * math.sin(yaw) + dz * math.cos(yaw)
            local_x = dx * math.cos(yaw) - dz * math.sin(yaw)
            dist_sq = local_x * local_x + local_z * local_z
            recovery_steer = 0.0
            if dist_sq > 0.01:
                recovery_steer = math.atan2(2.0 * self.wheelbase * local_x, dist_sq)
            recovery_steer = max(-0.5236, min(0.5236, recovery_steer))

            actual_dir = 0
            if speed > 0.2:
                actual_dir = 1
            elif speed < -0.2:
                actual_dir = -1
            effective_dir = actual_dir if actual_dir != 0 else 1
            if effective_dir == -1:
                recovery_steer *= -1

            print(f"[Tracker] OFF-GRID (cell {col},{row}). Recuperando hacia ({rx:.1f},{rz:.1f}). Dist={dist_to_recovery:.1f}m")
            orders = {
                "type": "orders",
                "steering": recovery_steer,
                "engine_force": 200.0,
                "brake": 15.0,
                "direction": 1,
                "current_waypoint_index": 0,
                "target_point": {"x": rx, "z": rz}
            }
            return self._apply_anti_stuck(orders, speed)

        if self._off_grid:
            print("[Tracker] Recuperado: de vuelta en terreno navegable.")
            self._off_grid = False
            self._recovery_target = None

        if not self.path:
            return {
                "type": "orders",
                "steering": 0.0,
                "engine_force": 0.0,
                "brake": 30.0,
                "direction": 1,
                "current_waypoint_index": 0,
                "target_point": None
            }

        # 1. Check current waypoint index
        node = self.path[self.current_index]
        d = math.hypot(node['x'] - x, node['z'] - z)

        arrival_threshold = 2.0
        # If next node is a direction shift, we need higher precision
        if self.current_index + 1 < len(self.path):
            next_node = self.path[self.current_index + 1]
            if next_node.get('direction', 1) != node.get('direction', 1):
                arrival_threshold = 0.5

        # Check if we passed the waypoint
        has_passed = False
        if self.current_index > 0:
            prev_node = self.path[self.current_index - 1]
            seg_x = node['x'] - prev_node['x']
            seg_z = node['z'] - prev_node['z']
            seg_len = math.hypot(seg_x, seg_z)
            if seg_len > 0.01:
                seg_dx = seg_x / seg_len
                seg_dz = seg_z / seg_len
                to_veh_x = x - node['x']
                to_veh_z = z - node['z']
                dot = to_veh_x * seg_dx + to_veh_z * seg_dz
                if dot > 0:
                    has_passed = True

        if d < arrival_threshold or has_passed:
            will_change_dir = False
            if self.current_index + 1 < len(self.path):
                next_node = self.path[self.current_index + 1]
                will_change_dir = next_node.get('direction', 1) != node.get('direction', 1)

            if will_change_dir and abs(speed) > 0.1:
                # Wait until vehicle stops before changing gear
                return {
                    "type": "orders",
                    "steering": 0.0,
                    "engine_force": 0.0,
                    "brake": 25.0,
                    "direction": node.get('direction', 1),
                    "current_waypoint_index": self.current_index,
                    "target_point": {"x": node['x'], "z": node['z']}
                }

            if self.current_index < len(self.path) - 1:
                self.current_index += 1
                node = self.path[self.current_index]
                print(f"[Tracker] Advanced to waypoint {self.current_index}/{len(self.path)-1} (d={d:.2f})")
            else:
                print("[Tracker] Destination reached successfully!")
                self.path = []
                return {
                    "type": "orders",
                    "steering": 0.0,
                    "engine_force": 0.0,
                    "brake": 30.0,
                    "direction": 1,
                    "current_waypoint_index": self.current_index,
                    "target_point": None,
                    "completed": True
                }

        # 2. Lookahead logic
        is_maneuver = False
        if self.current_index + 1 < len(self.path):
            next_node = self.path[self.current_index + 1]
            is_maneuver = next_node.get('direction', 1) != node.get('direction', 1)

        lookahead_dist = 0.2 if is_maneuver else 1.8
        if self.current_index < 5:
            lookahead_dist = 1.5

        lookahead_index = self.current_index
        current_dir = node.get('direction', 1)

        for i in range(self.current_index, len(self.path)):
            if self.path[i].get('direction', 1) != current_dir:
                lookahead_index = max(self.current_index, i - 1)
                break
            p = self.path[i]
            dist = math.hypot(p['x'] - x, p['z'] - z)
            if dist >= lookahead_dist:
                lookahead_index = i
                break
            lookahead_index = i

        target = self.path[lookahead_index]
        desired_dir = target.get('direction', 1)

        # 3. Steering calculations (Pure Pursuit on rear axle reference point)
        rear_x = x - (self.wheelbase * 0.5) * math.sin(yaw)
        rear_z = z - (self.wheelbase * 0.5) * math.cos(yaw)

        dx = target['x'] - rear_x
        dz = target['z'] - rear_z

        # Rotate to vehicle local frame (+Z front, +X left)
        local_z = dx * math.sin(yaw) + dz * math.cos(yaw)
        local_x = dx * math.cos(yaw) - dz * math.sin(yaw)

        distance_squared = local_x * local_x + local_z * local_z
        target_steering = 0.0
        if distance_squared > 0.01:
            target_steering = math.atan2(2.0 * self.wheelbase * local_x, distance_squared)

        # Max Ackerman steering limit (30 degrees / 0.5236 rad)
        max_steer = 0.5236
        target_steering = max(-max_steer, min(max_steer, target_steering))

        # Invert steering if reversing
        actual_motion_dir = 0
        if speed > 0.2:
            actual_motion_dir = 1
        elif speed < -0.2:
            actual_motion_dir = -1

        effective_dir = actual_motion_dir if actual_motion_dir != 0 else desired_dir
        if effective_dir == -1:
            target_steering *= -1

        # 4. Aceleration and speed control
        target_speed = self.max_speed

        target_speed = max(target_speed, 0.5)

        # Direction changes: stop first
        is_wrong_way = (speed > 1.5 and desired_dir == 1) or (speed < -1.5 and desired_dir == -1)

        if is_wrong_way:
            print(f"[Tracker] WRONG WAY: speed={speed:.2f}, desired_dir={desired_dir}. Frenando.")
            engine_force = 0.0
            brake = 30.0
        else:
            speed_diff = target_speed - abs(speed)
            max_force = self.torque * 2.0
            if speed_diff > 0:
                engine_force = min(speed_diff * 40.0, max_force)
                brake = 0.0
            else:
                engine_force = 0.0
                brake = min(abs(speed_diff) * 2.5, 35.0)

        orders = {
            "type": "orders",
            "steering": target_steering,
            "engine_force": engine_force,
            "brake": brake,
            "direction": desired_dir,
            "current_waypoint_index": self.current_index,
            "target_point": {"x": target['x'], "z": target['z']}
        }

        # Blend obstacle avoidance from rover's circular zones
        if evasion_data:
            inner = evasion_data.get("inner_count", 0)
            middle = evasion_data.get("middle_count", 0)
            outer = evasion_data.get("outer_count", 0)
            ev_lateral = evasion_data.get("lateral", 0.0)
            ev_brake = evasion_data.get("brake", 0.0)

            if inner > 0 or middle > 0 or outer > 0:
                orders["steering"] += ev_lateral * 0.3
                if ev_brake > 0:
                    orders["engine_force"] = 0
                    orders["brake"] = max(orders["brake"], ev_brake)

        return self._apply_anti_stuck(orders, speed)

# WebSockets Server
tracker = PathTracker()
connected_clients = set()

async def broadcast(message):
    if not connected_clients:
        return
    message_str = json.dumps(message)
    # Gather and await sending to all clients
    await asyncio.gather(
        *(client.send(message_str) for client in connected_clients),
        return_exceptions=True
    )

async def handler(websocket):
    print(f"[Logic Server] Client connected from {websocket.remote_address}")
    connected_clients.add(websocket)
    try:
        async for message_str in websocket:
            try:
                data = json.loads(message_str)
            except json.JSONDecodeError:
                print(f"[Logic Server] Non-JSON payload received: {message_str}")
                continue

            msg_type = data.get("type")

            if msg_type == "init_level":
                global _level_tiles, _level_spacing
                _level_tiles = data.get("tiles", [])
                _level_spacing = data.get("tile_spacing", 4.0)
                print(f"[Logic Server] Grid initialized: {len(_level_tiles)}x{len(_level_tiles[0]) if _level_tiles else 0}, spacing={_level_spacing}")
                await websocket.send(json.dumps({"type": "level_initialized"}))

            elif msg_type == "calculate_path":
                start_data = data.get("start", {})
                goal_data = data.get("goal", {})
                start_col = round(start_data["x"] / _level_spacing)
                start_row = round(start_data["z"] / _level_spacing)
                goal_col = round(goal_data["x"] / _level_spacing)
                goal_row = round(goal_data["z"] / _level_spacing)

                print(f"[Logic Server] Pathfinding: ({start_col},{start_row}) -> ({goal_col},{goal_row})")
                path = a_star_pathfinding(start_col, start_row, goal_col, goal_row)

                if path:
                    await websocket.send(json.dumps({"type": "path_calculated", "path": path}))
                    print(f"[Logic Server] Path found with {len(path)} waypoints.")
                else:
                    await websocket.send(json.dumps({"type": "path_failed"}))
                    print("[Logic Server] No path found.")

            elif msg_type == "set_path":
                raw_path = data.get("path", [])
                tracker.set_path(raw_path)
                # Broadcast confirmation
                await broadcast({
                    "type": "path_confirmed",
                    "length": len(raw_path)
                })

            elif msg_type == "telemetry":
                x = data.get("x", 0.0)
                z = data.get("z", 0.0)
                yaw = data.get("heading", 0.0)
                speed = data.get("speed", 0.0)
                config_data = data.get("config")
                evasion_data = data.get("evasion")

                orders = tracker.update(x, z, yaw, speed, config_data, evasion_data)
                await broadcast(orders)

            elif msg_type == "stop":
                tracker.stop()
                await broadcast({
                    "type": "orders",
                    "steering": 0.0,
                    "engine_force": 0.0,
                    "brake": 30.0,
                    "direction": 1,
                    "current_waypoint_index": 0,
                    "target_point": None
                })

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        connected_clients.remove(websocket)
        print(f"[Logic Server] Client disconnected from {websocket.remote_address}")

async def main():
    print(f"[Logic Server] Logic Subsystem running at ws://{WS_HOST}:{WS_PORT}")
    async with websockets.serve(handler, WS_HOST, WS_PORT):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
