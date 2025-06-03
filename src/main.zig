const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const DEBUG: bool = true;
const THRUST_STRENGTH: f32 = 500;
const ROTATION_SPEED: f32 = 2.5;
const SHOOT_INTERVAL: f32 = 0.1;

const ASTEROID_BASE_SPEED: f32 = 300;
const ASTEROID_MINIMUM_SIZE: f32 = 20;
const ASTEROID_MAXIMUM_SIZE: f32 = 200;
const ASTEROID_SPAWN_CHANCE: f32 = 0.1;
const ASTEROID_STOP_SPAWN_COUNT: u16 = 40;
const ASTEROID_SPAWN_INTERVAL: f32 = 0.5;

const BULLET_BASE_SPEED: f32 = 800;

const WINDOW_WIDTH: u16 = 1920;
const WINDOW_HEIGHT: u16 = 1080;
const DEAD_ZONE_WIDTH: u16 = 1000;
const DEAD_ZONE_HEIGHT: u16 = 600;
const DEAD_ZONE = raylib.Rectangle{
    .x = (WINDOW_WIDTH - DEAD_ZONE_WIDTH) / 2,
    .y = (WINDOW_HEIGHT - DEAD_ZONE_HEIGHT) / 2,
    .width = DEAD_ZONE_WIDTH,
    .height = DEAD_ZONE_HEIGHT,
};

const NUM_STARS: u16 = 500;
const STAR_AREA: u16 = 3000;

const ZONE_SIZE_WORLD = 2048;

const SPAWN_RADIUS: u16 = 1500;
const KILL_RADIUS: u16 = 1600;

const GAME_MODE = enum { startMenu, game, paused, map };

var stars: [NUM_STARS]raylib.Vector3 = undefined;

pub fn isTurnLeft() bool {
    if (raylib.IsKeyDown(raylib.KEY_A) or raylib.IsKeyDown(raylib.KEY_LEFT)) {
        // std.debug.print("Turning Left", .{});
        return true;
    }
    return false;
}
pub fn isTurnRight() bool {
    if (raylib.IsKeyDown(raylib.KEY_D) or raylib.IsKeyDown(raylib.KEY_RIGHT)) {
        // std.debug.print("Turning Right", .{});
        return true;
    }
    return false;
}
pub fn isThrusterOn() bool {
    if (raylib.IsKeyDown(raylib.KEY_W) or raylib.IsKeyDown(raylib.KEY_UP)) {
        // std.debug.print("Thrust", .{});
        return true;
    }
    return false;
}
pub fn isShooting() bool {
    // std.debug.print("Shoot!", .{});
    return raylib.IsKeyDown(raylib.KEY_SPACE);
}

pub const GameState = struct {
    camera: Camera2D,
    player: Spaceship,
    bullets: std.ArrayList(Bullet),
    bullets_last_shot: f64,
    asteroids: std.ArrayList(Asteroid),
    asteroid_last_spawn: f64,
    playerIsAlive: bool,
};
var STATE: GameState = undefined;

pub const Utilities = struct {
    rand: std.Random,
    allocator: std.mem.Allocator,
};
var UTILS: Utilities = undefined;

pub const Transform2D = struct {
    position: raylib.Vector2,
    rotation: f32,
    velocity: raylib.Vector2,

    pub fn cos_theta(self: *const Transform2D) f32 {
        return std.math.cos(self.rotation);
    }

    pub fn sin_theta(self: *const Transform2D) f32 {
        return std.math.sin(self.rotation);
    }

    pub fn forward(self: *const Transform2D) raylib.Vector2 {
        const cos = std.math.cos(self.rotation);
        const sin = std.math.sin(self.rotation);
        return raylib.Vector2{ .x = sin, .y = -cos };
    }

    pub fn update(self: *Transform2D, dt: f32) void {
        self.position.x += self.velocity.x * dt;
        self.position.y += self.velocity.y * dt;
    }
};

const Spaceship = struct {
    const ship_body: [3]raylib.Vector2 = .{
        raylib.Vector2{ .x = 0, .y = -10 }, // tail (bottom)
        raylib.Vector2{ .x = -5, .y = 10 }, // left
        raylib.Vector2{ .x = 5, .y = 10 }, // right
    };
    transform: Transform2D,

    pub fn getShipBody(self: *Spaceship) [3]raylib.Vector2 {
        var body: [3]raylib.Vector2 = undefined;
        for (ship_body, 0..) |point, i| {
            const cos = self.transform.cos_theta();
            const sin = self.transform.sin_theta();
            body[i] = raylib.Vector2{
                .x = self.transform.position.x + cos * point.x - sin * point.y,
                .y = self.transform.position.y + sin * point.x + cos * point.y,
            };
        }
        return body;
    }

    pub fn draw(self: *Spaceship) void {
        const body = ship_body;
        for (body, 0..) |_, i| {
            const j = (i + 1) % body.len;

            const local_p = body[i];
            const local_q = body[j];
            // move each vertex from local → world by adding position
            const p = raylib.Vector2{
                .x = self.transform.position.x + self.transform.cos_theta() * local_p.x - self.transform.sin_theta() * local_p.y,
                .y = self.transform.position.y + self.transform.sin_theta() * local_p.x + self.transform.cos_theta() * local_p.y,
            };
            const q = raylib.Vector2{
                .x = self.transform.position.x + self.transform.cos_theta() * local_q.x - self.transform.sin_theta() * local_q.y,
                .y = self.transform.position.y + self.transform.sin_theta() * local_q.x + self.transform.cos_theta() * local_q.y,
            };
            raylib.DrawLineV(p, q, raylib.RAYWHITE);
        }
    }
};

const Bullet = struct {
    transform: Transform2D,
    size: f32,

    pub fn draw(self: *const Bullet) void {
        raylib.DrawCircleLinesV(self.transform.position, self.size, raylib.GRAY);
    }
};

const Asteroid = struct {
    transform: Transform2D,
    size: f32,

    pub fn draw(self: *const Asteroid) void {
        raylib.DrawCircleLinesV(self.transform.position, self.size, raylib.GRAY);
    }

    pub fn checkForDelete(self: *Asteroid, camera: *Camera2D) bool {
        const vectorToCam = raylib.Vector2Subtract(camera.target, self.transform.position);
        const distToCam = raylib.Vector2Length(vectorToCam);
        if (distToCam >= KILL_RADIUS) {
            return true;
        }
        return false;
    }
};

const Camera2D = struct {
    target: raylib.Vector2,
    offset: raylib.Vector2,
    zoom: f32,

    pub fn init(screen_width: f32, screen_height: f32) Camera2D {
        return Camera2D{
            .target = raylib.Vector2{ .x = 0, .y = 0 },
            .offset = raylib.Vector2{ .x = screen_width / 2, .y = screen_height / 2 },
            .zoom = 1.0,
        };
    }

    pub fn toRaylib(self: *const Camera2D) raylib.Camera2D {
        return raylib.Camera2D{
            .target = self.target,
            .offset = self.offset,
            .rotation = 0.0,
            .zoom = self.zoom,
        };
    }
};

const Zone = struct {
    name: []const u8,
    bounds: raylib.Rectangle,
};

pub fn UpdatePlayer(dt: f32) !void {
    if (isTurnLeft()) {
        STATE.player.transform.rotation -= ROTATION_SPEED * dt;
    }
    if (isTurnRight()) {
        STATE.player.transform.rotation += ROTATION_SPEED * dt;
    }
    // const old_velocity = raylib.Vector2Length(ship.transform.velocity);
    if (isThrusterOn()) {
        const forward = STATE.player.transform.forward();
        // std.debug.print("Forward {d} {d}\n", .{ forward.x, forward.y });
        const thrust = raylib.Vector2{
            .x = forward.x * THRUST_STRENGTH * dt,
            .y = forward.y * THRUST_STRENGTH * dt,
        };

        STATE.player.transform.velocity.x += thrust.x;
        STATE.player.transform.velocity.y += thrust.y;
    }
    // Apply Velocity
    STATE.player.transform.position.x += STATE.player.transform.velocity.x * dt;
    STATE.player.transform.position.y += STATE.player.transform.velocity.y * dt;
    const current_time = raylib.GetTime();
    if (isShooting()) {
        if (SHOOT_INTERVAL < current_time - STATE.bullets_last_shot) {
            STATE.bullets_last_shot = current_time;
            const direction = STATE.player.transform.forward();
            try STATE.bullets.append(Bullet{
                .transform = Transform2D{
                    .position = STATE.player.transform.position,
                    .rotation = 0,
                    .velocity = raylib.Vector2Add(
                        STATE.player.transform.velocity,
                        raylib.Vector2Scale(direction, BULLET_BASE_SPEED),
                    ),
                },
                .size = 2,
            });
        }
    }

    // std.debug.print("New velocity {d} -> {d}\n", .{ old_velocity, raylib.Vector2Length(ship.transform.velocity) });
    // Thrust decay
    STATE.player.transform.velocity = raylib.Vector2Scale(STATE.player.transform.velocity, 1 - (0.4 * dt));
}

pub fn UpdateCamera() void {
    const player_pos = STATE.player.transform.position;
    const screen_pos = raylib.Vector2{
        .x = player_pos.x - STATE.camera.target.x + STATE.camera.offset.x,
        .y = player_pos.y - STATE.camera.target.y + STATE.camera.offset.y,
    };

    if (screen_pos.x < DEAD_ZONE.x) {
        STATE.camera.target.x -= DEAD_ZONE.x - screen_pos.x;
    } else if (screen_pos.x > DEAD_ZONE.x + DEAD_ZONE.width) {
        STATE.camera.target.x += screen_pos.x - (DEAD_ZONE.x + DEAD_ZONE.width);
    }

    if (screen_pos.y < DEAD_ZONE.y) {
        STATE.camera.target.y -= DEAD_ZONE.y - screen_pos.y;
    } else if (screen_pos.y > DEAD_ZONE.y + DEAD_ZONE.height) {
        STATE.camera.target.y += screen_pos.y - (DEAD_ZONE.y + DEAD_ZONE.height);
    }
}

pub fn UpdateAsteroids(dt: f32) void {
    var i: usize = STATE.asteroids.items.len;
    while (i > 0) {
        i -= 1;
        if (STATE.asteroids.items[i].checkForDelete(&STATE.camera)) {
            // allocator.destroy(Asteroid);
            _ = STATE.asteroids.swapRemove(i);
            // std.debug.print("Kill Asteroid {}", .{i});
        } else {
            STATE.asteroids.items[i].transform.update(dt);
            // asteroid.transform.position.x += asteroid.size
            // std.debug.print("Updated Asteroid {}", .{i});
        }
    }
}

pub fn SpawnAsteroids() !void {
    const current_time = raylib.GetTime();
    if (ASTEROID_SPAWN_INTERVAL < current_time - STATE.asteroid_last_spawn) {
        if (UTILS.rand.float(f32) < ASTEROID_SPAWN_CHANCE) {
            STATE.asteroid_last_spawn = current_time;
            try STATE.asteroids.append(GetNewAsteroid());
        }
    }
}

pub fn CheckForBulletHit() !void {
    var i = STATE.asteroids.items.len;
    while (i > 0) {
        i -= 1;
        var j = STATE.bullets.items.len;
        while (j > 0) {
            j -= 1;
            const distance = raylib.Vector2Distance(
                STATE.asteroids.items[i].transform.position,
                STATE.bullets.items[j].transform.position,
            );
            if (distance < STATE.asteroids.items[i].size) {
                // std.debug.print("Asteroid Hit", .{});
                _ = STATE.asteroids.swapRemove(i);
                _ = STATE.bullets.swapRemove(j);
                break;
            }
        }
    }
}

pub fn CheckForHitsOnShip() bool {
    const ship_body = STATE.player.getShipBody();
    for (STATE.asteroids.items) |asteroid| {
        for (ship_body) |point| {
            if (raylib.Vector2Distance(asteroid.transform.position, point) < asteroid.size) {
                return true;
            }
        }
    }
    return false;
}

fn rotateVector(v: raylib.Vector2, angle: f32) raylib.Vector2 {
    return raylib.Vector2{
        .x = v.x * @cos(angle) - v.y * @sin(angle),
        .y = v.x * @sin(angle) + v.y * @cos(angle),
    };
}

pub fn GetNewAsteroid() Asteroid {
    const spawnDirection = raylib.Vector2{
        .x = raylib.Lerp(-1, 1, UTILS.rand.float(f32)),
        .y = raylib.Lerp(-1, 1, UTILS.rand.float(f32)),
    };
    var spawnFrom = raylib.Vector2Normalize(spawnDirection);

    const angle = UTILS.rand.float(f32) * std.math.pi - (std.math.pi / 2.0); // ±90°
    const inverted = raylib.Vector2{ .x = spawnFrom.x * -1, .y = spawnFrom.y * -1 };
    const move_direction = raylib.Vector2Normalize(rotateVector(inverted, angle));
    const velocity = raylib.Vector2{
        .x = move_direction.x * ASTEROID_BASE_SPEED,
        .y = move_direction.y * ASTEROID_BASE_SPEED,
    };

    spawnFrom = raylib.Vector2Multiply(spawnFrom, raylib.Vector2{
        .x = SPAWN_RADIUS,
        .y = SPAWN_RADIUS,
    });
    spawnFrom = raylib.Vector2Add(STATE.camera.target, spawnFrom);

    if (DEBUG) {
        // std.debug.print("Cam offset: {d:.2}, {d:.2}", .{ cam.offset.x, cam.offset.y });
        //std.debug.print(
        //    "Spawning asteroid at ({d:.2}, {d:.2}) heading toward ({d:.2}, {d:.2})\n",
        //    .{ spawnFrom.x, spawnFrom.y, velocity.x, velocity.y },
        //);
    }

    return Asteroid{
        .transform = Transform2D{
            .position = spawnFrom,
            .velocity = velocity,
            .rotation = 0,
        },
        // .size = 20 + rng.float(f32) * 20,
        .size = raylib.Lerp(
            ASTEROID_MINIMUM_SIZE,
            ASTEROID_MAXIMUM_SIZE,
            UTILS.rand.float(f32),
        ),
    };
}

pub fn main() !void {
    raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Zig Asteroids");
    defer raylib.CloseWindow();

    // Init system variables
    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
        std.debug.print("Failed to get random seed: {}\n", .{err});
        return;
    };
    var prng = std.Random.DefaultPrng.init(seed);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    UTILS = .{
        .allocator = gpa.allocator(),
        .rand = prng.random(),
    };

    while (!raylib.WindowShouldClose()) {
        // var playerIsAlive = true;
        STATE.playerIsAlive = true;
        // Init game instance
        STATE.player = Spaceship{ .transform = .{
            .position = raylib.Vector2{ .x = 0, .y = 0 },
            .rotation = 0,
            .velocity = raylib.Vector2{ .x = 0, .y = 0 },
        } };

        STATE.camera = Camera2D.init(WINDOW_WIDTH, WINDOW_HEIGHT);
        // defer camera.deinit();

        for (&stars) |*star| {
            star.* = raylib.Vector3{
                .x = UTILS.rand.float(f32) * STAR_AREA - STAR_AREA / 2,
                .y = UTILS.rand.float(f32) * STAR_AREA - STAR_AREA / 2,
                .z = UTILS.rand.float(f32) / 2 + 0.5,
            };
        }

        var zones = std.ArrayList(Zone).init(UTILS.allocator);
        defer zones.deinit();
        try zones.append(Zone{ .name = "Home", .bounds = raylib.Rectangle{
            .x = -1,
            .y = -1,
            .width = 2,
            .height = 2,
        } });

        STATE.asteroids = std.ArrayList(Asteroid).init(UTILS.allocator);
        defer STATE.asteroids.deinit();
        STATE.asteroid_last_spawn = 0.0;

        STATE.bullets = std.ArrayList(Bullet).init(UTILS.allocator);
        defer STATE.bullets.deinit();
        STATE.bullets_last_shot = 0.0;

        while (STATE.playerIsAlive and !raylib.WindowShouldClose()) {

            //Update
            const dt = raylib.GetFrameTime();
            try UpdatePlayer(dt);
            UpdateCamera();
            UpdateAsteroids(dt);
            try SpawnAsteroids();

            var i = STATE.bullets.items.len;
            while (i > 0) {
                i -= 1;
                STATE.bullets.items[i].transform.update(dt);
            }
            try CheckForBulletHit();
            STATE.playerIsAlive = !CheckForHitsOnShip();

            //Draw
            raylib.BeginDrawing();
            raylib.ClearBackground(raylib.BLACK);
            // Draw with camera
            raylib.BeginMode2D(STATE.camera.toRaylib());

            for (stars) |star| {
                const parallax_pos = raylib.Vector2{
                    .x = star.x * star.z,
                    .y = star.y * star.z,
                };
                raylib.DrawRectangleV(parallax_pos, raylib.Vector2{ .x = 2, .y = 2 }, raylib.GRAY);
            }

            STATE.player.draw();

            for (STATE.asteroids.items) |asteroid| {
                asteroid.draw();
            }
            for (STATE.bullets.items) |bullet| {
                bullet.draw();
            }

            for (zones.items) |zone| {
                raylib.DrawRectangleLines(
                    @intFromFloat(zone.bounds.x * ZONE_SIZE_WORLD),
                    @intFromFloat(zone.bounds.y * ZONE_SIZE_WORLD),
                    @intFromFloat(zone.bounds.width * ZONE_SIZE_WORLD),
                    @intFromFloat(zone.bounds.height * ZONE_SIZE_WORLD),
                    raylib.BLUE,
                );
            }

            raylib.EndMode2D();

            // (Optional) draw world space debug stuff here
            if (DEBUG) {
                raylib.DrawRectangleLines(
                    @intFromFloat(DEAD_ZONE.x),
                    @intFromFloat(DEAD_ZONE.y),
                    @intFromFloat(DEAD_ZONE.width),
                    @intFromFloat(DEAD_ZONE.height),
                    raylib.GRAY,
                );
                const formatted = try std.fmt.allocPrint(UTILS.allocator, "Cell ({d}, {d})", .{
                    std.math.floor(STATE.player.transform.position.x / ZONE_SIZE_WORLD),
                    std.math.floor(STATE.player.transform.position.y / ZONE_SIZE_WORLD),
                });
                defer UTILS.allocator.free(formatted);

                const num_asteroids = try std.fmt.allocPrint(UTILS.allocator, "Asteroids: {d}", .{STATE.asteroids.items.len});
                defer UTILS.allocator.free(num_asteroids);

                const camera_info = try std.fmt.allocPrint(UTILS.allocator, "Camera: target({d}.{d}) offset({d},{d})", .{
                    STATE.camera.target.x,
                    STATE.camera.target.y,
                    STATE.camera.offset.x,
                    STATE.camera.offset.y,
                });
                defer UTILS.allocator.free(camera_info);

                raylib.DrawText(formatted.ptr, @intFromFloat(0), @intFromFloat(0), 20, raylib.GRAY);
                raylib.DrawText(num_asteroids.ptr, @intFromFloat(0), @intFromFloat(25), 20, raylib.GRAY);
                raylib.DrawText(camera_info.ptr, @intFromFloat(0), @intFromFloat(50), 20, raylib.GRAY);
            }
            // (Optional) draw UI / HUD here (in screen space)

            raylib.EndDrawing();
        }
    }
}
