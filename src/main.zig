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
const BULLET_BASE_SPEED: f32 = 500;

const WINDOW_WIDTH: u16 = 1920;
const WINDOW_HEIGHT: u16 = 1080;
const DEAD_ZONE = raylib.Rectangle{
    .x = (1920 - 1280) / 2,
    .y = (1080 - 720) / 2,
    .width = 1280,
    .height = 720,
};

const NUM_STARS: u16 = 500;
const STAR_AREA: u16 = 3000;

const ZONE_SIZE_WORLD = 2048;

const SPAWN_RADIUS: u16 = 1000;
const KILL_RADIUS: u16 = 1200;

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

pub fn UpdatePlayer(dt: f32, ship: *Spaceship, bullets: *std.ArrayList(Bullet), bullets_last_shot: *f64) !void {
    if (isTurnLeft()) {
        ship.transform.rotation -= ROTATION_SPEED * dt;
    }
    if (isTurnRight()) {
        ship.transform.rotation += ROTATION_SPEED * dt;
    }
    // const old_velocity = raylib.Vector2Length(ship.transform.velocity);
    if (isThrusterOn()) {
        const forward = ship.transform.forward();
        // std.debug.print("Forward {d} {d}\n", .{ forward.x, forward.y });
        const thrust = raylib.Vector2{
            .x = forward.x * THRUST_STRENGTH * dt,
            .y = forward.y * THRUST_STRENGTH * dt,
        };

        ship.transform.velocity.x += thrust.x;
        ship.transform.velocity.y += thrust.y;
    }
    // Apply Velocity
    ship.transform.position.x += ship.transform.velocity.x * dt;
    ship.transform.position.y += ship.transform.velocity.y * dt;
    const current_time = raylib.GetTime();
    if (isShooting()) {
        if (SHOOT_INTERVAL < current_time - bullets_last_shot.*) {
            bullets_last_shot.* = current_time;
            const direction = ship.transform.forward();
            try bullets.append(Bullet{
                .transform = Transform2D{
                    .position = ship.transform.position,
                    .rotation = 0,
                    .velocity = raylib.Vector2Add(
                        ship.transform.velocity,
                        raylib.Vector2Scale(direction, BULLET_BASE_SPEED),
                    ),
                },
                .size = 2,
            });
        }
    }

    // std.debug.print("New velocity {d} -> {d}\n", .{ old_velocity, raylib.Vector2Length(ship.transform.velocity) });
    // Thrust decay
    ship.transform.velocity = raylib.Vector2Scale(ship.transform.velocity, 1 - (0.4 * dt));
}

pub fn UpdateCamera(cam: *Camera2D, player_pos: raylib.Vector2) void {
    const screen_pos = raylib.Vector2{
        .x = player_pos.x - cam.target.x + cam.offset.x,
        .y = player_pos.y - cam.target.y + cam.offset.y,
    };

    if (screen_pos.x < DEAD_ZONE.x) {
        cam.target.x -= DEAD_ZONE.x - screen_pos.x;
    } else if (screen_pos.x > DEAD_ZONE.x + DEAD_ZONE.width) {
        cam.target.x += screen_pos.x - (DEAD_ZONE.x + DEAD_ZONE.width);
    }

    if (screen_pos.y < DEAD_ZONE.y) {
        cam.target.y -= DEAD_ZONE.y - screen_pos.y;
    } else if (screen_pos.y > DEAD_ZONE.y + DEAD_ZONE.height) {
        cam.target.y += screen_pos.y - (DEAD_ZONE.y + DEAD_ZONE.height);
    }
}

pub fn CheckForBulletHit(
    bullets: *std.ArrayList(Bullet),
    asteroids: *std.ArrayList(Asteroid),
) !void {
    var i = asteroids.items.len;
    while (i > 0) {
        i -= 1;
        var j = bullets.items.len;
        while (j > 0) {
            j -= 1;
            const distance = raylib.Vector2Distance(
                asteroids.items[i].transform.position,
                bullets.items[j].transform.position,
            );
            if (distance < asteroids.items[i].size) {
                // std.debug.print("Asteroid Hit", .{});
                _ = asteroids.swapRemove(i);
                _ = bullets.swapRemove(j);
                break;
            }
        }
    }
}

fn rotateVector(v: raylib.Vector2, angle: f32) raylib.Vector2 {
    return raylib.Vector2{
        .x = v.x * @cos(angle) - v.y * @sin(angle),
        .y = v.x * @sin(angle) + v.y * @cos(angle),
    };
}

pub fn GetNewAsteroid(rng: *const std.Random, cam: *Camera2D) Asteroid {
    const spawnDirection = raylib.Vector2{ .x = rng.float(f32), .y = rng.float(f32) };
    var spawnFrom = raylib.Vector2Normalize(spawnDirection);

    const angle = rng.float(f32) * std.math.pi - (std.math.pi / 2.0); // ±90°
    const inverted = raylib.Vector2{ .x = spawnFrom.x * -1, .y = spawnFrom.y * -1 };
    const move_direction = raylib.Vector2Normalize(rotateVector(inverted, angle));
    const velocity = raylib.Vector2{ .x = move_direction.x * ASTEROID_BASE_SPEED, .y = move_direction.y * ASTEROID_BASE_SPEED };

    spawnFrom = raylib.Vector2Multiply(spawnFrom, raylib.Vector2{ .x = SPAWN_RADIUS, .y = SPAWN_RADIUS });
    spawnFrom = raylib.Vector2Add(cam.target, spawnFrom);

    if (DEBUG) {
        // std.debug.print("Cam offset: {d:.2}, {d:.2}", .{ cam.offset.x, cam.offset.y });
        //std.debug.print(
        //    "Spawning asteroid at ({d:.2}, {d:.2}) heading toward ({d:.2}, {d:.2})\n",
        //    .{ spawnFrom.x, spawnFrom.y, velocity.x, velocity.y },
        //);
    }

    return Asteroid{
        .transform = Transform2D{ .position = spawnFrom, .velocity = velocity, .rotation = 0 },
        .size = 20 + rng.float(f32) * 20,
    };
}

pub fn main() !void {
    raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Zig + raylib Minimal");
    defer raylib.CloseWindow();

    var ship = Spaceship{ .transform = .{
        .position = raylib.Vector2{ .x = 0, .y = 0 },
        .rotation = 0,
        .velocity = raylib.Vector2{ .x = 0, .y = 0 },
    } };

    var camera = Camera2D.init(WINDOW_WIDTH, WINDOW_HEIGHT);

    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch |err| {
        std.debug.print("Failed to get random seed: {}\n", .{err});
        return;
    };

    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (&stars) |*star| {
        star.* = raylib.Vector3{ .x = rand.float(f32) * STAR_AREA - STAR_AREA / 2, .y = rand.float(f32) * STAR_AREA - STAR_AREA / 2, .z = rand.float(f32) / 2 + 0.5 };
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var zones = std.ArrayList(Zone).init(allocator);
    defer zones.deinit();
    try zones.append(Zone{ .name = "Home", .bounds = raylib.Rectangle{
        .x = -1,
        .y = -1,
        .width = 2,
        .height = 2,
    } });

    var asteroids = std.ArrayList(Asteroid).init(allocator);
    defer asteroids.deinit();

    var bullets = std.ArrayList(Bullet).init(allocator);
    defer bullets.deinit();
    var bullets_last_shot: f64 = 0.0;

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        //Update
        const dt = raylib.GetFrameTime();
        try UpdatePlayer(dt, &ship, &bullets, &bullets_last_shot);
        UpdateCamera(&camera, ship.transform.position);

        var i: usize = asteroids.items.len;
        while (i > 0) {
            i -= 1;
            if (asteroids.items[i].checkForDelete(&camera)) {
                // allocator.destroy(Asteroid);
                _ = asteroids.swapRemove(i);
                // std.debug.print("Kill Asteroid {}", .{i});
            } else {
                asteroids.items[i].transform.update(dt);
                // asteroid.transform.position.x += asteroid.size
                // std.debug.print("Updated Asteroid {}", .{i});
            }
        }
        if (asteroids.items.len < 8) {
            try asteroids.append(GetNewAsteroid(&rand, &camera));
        }

        i = bullets.items.len;
        while (i > 0) {
            i -= 1;
            bullets.items[i].transform.update(dt);
        }
        try CheckForBulletHit(&bullets, &asteroids);

        //Draw
        // Draw with camera
        raylib.BeginMode2D(camera.toRaylib());

        for (stars) |star| {
            const parallax_pos = raylib.Vector2{
                .x = star.x * star.z,
                .y = star.y * star.z,
            };
            raylib.DrawRectangleV(parallax_pos, raylib.Vector2{ .x = 2, .y = 2 }, raylib.GRAY);
        }

        ship.draw();

        for (asteroids.items) |asteroid| {
            asteroid.draw();
        }
        for (bullets.items) |bullet| {
            bullet.draw();
        }

        for (zones.items) |zone| {
            raylib.DrawRectangleLines(@intFromFloat(zone.bounds.x * ZONE_SIZE_WORLD), @intFromFloat(zone.bounds.y * ZONE_SIZE_WORLD), @intFromFloat(zone.bounds.width * ZONE_SIZE_WORLD), @intFromFloat(zone.bounds.height * ZONE_SIZE_WORLD), raylib.BLUE);
        }

        raylib.EndMode2D();

        // (Optional) draw world space debug stuff here
        if (DEBUG) {
            raylib.DrawRectangleLines(@intFromFloat(DEAD_ZONE.x), @intFromFloat(DEAD_ZONE.y), @intFromFloat(DEAD_ZONE.width), @intFromFloat(DEAD_ZONE.height), raylib.GRAY);
            const formatted = try std.fmt.allocPrint(allocator, "Cell ({d}, {d})", .{ std.math.floor(ship.transform.position.x / ZONE_SIZE_WORLD), std.math.floor(ship.transform.position.y / ZONE_SIZE_WORLD) });
            defer allocator.free(formatted);

            const num_asteroids = try std.fmt.allocPrint(allocator, "Asteroids: {d}", .{asteroids.items.len});
            defer allocator.free(num_asteroids);

            const camera_info = try std.fmt.allocPrint(allocator, "Camera: target({d}.{d}) offset({d},{d})", .{ camera.target.x, camera.target.y, camera.offset.x, camera.offset.y });
            defer allocator.free(camera_info);

            raylib.DrawText(formatted.ptr, @intFromFloat(0), @intFromFloat(0), 20, raylib.GRAY);
            raylib.DrawText(num_asteroids.ptr, @intFromFloat(0), @intFromFloat(25), 20, raylib.GRAY);
            raylib.DrawText(camera_info.ptr, @intFromFloat(0), @intFromFloat(50), 20, raylib.GRAY);
        }
        // (Optional) draw UI / HUD here (in screen space)

        raylib.EndDrawing();
    }
}
