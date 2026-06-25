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

class PathTracker:
    def __init__(self):
        self.path = []
        self.current_index = 0
        self.max_speed = 7.5       # Default maximum speed
        self.wheelbase = 2.0       # Distance between axles
        self.torque = 300.0        # Engine torque multiplier

    def set_path(self, path):
        self.path = path
        self.current_index = 0
        print(f"[Tracker] New path set with {len(path)} waypoints.")

    def stop(self):
        self.path = []
        self.current_index = 0
        print("[Tracker] Tracking stopped.")

    def update(self, x, z, yaw, speed, config_data=None):
        if config_data:
            self.max_speed = config_data.get("max_speed", self.max_speed)
            self.wheelbase = config_data.get("wheelbase", self.wheelbase)
            self.torque = config_data.get("torque", self.torque)

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

        # Corner slowdown
        approaching_corner = False
        for k in range(self.current_index, min(self.current_index + 3, len(self.path))):
            if abs(self.path[k].get('steer', 0)) > 0.1:
                approaching_corner = True
                break

        if approaching_corner:
            target_speed = min(target_speed, 3.2)

        # Final destination deceleration
        distance_to_final = math.hypot(self.path[-1]['x'] - x, self.path[-1]['z'] - z)
        braking_distance = 12.0
        if distance_to_final < braking_distance:
            speed_factor = distance_to_final / braking_distance
            target_speed = min(target_speed, self.max_speed * speed_factor * speed_factor)

        target_speed = max(target_speed, 0.5)

        # Direction changes: stop first
        is_wrong_way = (speed > 1.5 and desired_dir == -1) or (speed < -1.5 and desired_dir == 1)

        if is_wrong_way:
            engine_force = 0.0
            brake = 30.0
        else:
            if abs(speed) < target_speed:
                engine_force = self.torque * 2.0
                brake = 0.0
            else:
                engine_force = 0.0
                brake_strength = 10.0 + (abs(speed) - target_speed) * 2.0
                brake = min(brake_strength, 35.0)

        return {
            "type": "orders",
            "steering": target_steering,
            "engine_force": engine_force,
            "brake": brake,
            "direction": desired_dir,
            "current_waypoint_index": self.current_index,
            "target_point": {"x": target['x'], "z": target['z']}
        }

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

            if msg_type == "set_path":
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
                yaw = data.get("yaw", 0.0)
                speed = data.get("speed", 0.0)
                config_data = data.get("config")

                orders = tracker.update(x, z, yaw, speed, config_data)
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
