const std = @import("std");
const raylib = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const DEBUG: bool = true;
const THRUST_STRENGTH: f32 = 500;
const ROTATION_SPEED: f32 = 2.5;

const WINDOW_WIDTH: u16 = 800;
const WINDOW_HEIGHT: u16 = 600;
const DEAD_ZONE = raylib.Rectangle{
    .x = 200,
    .y = 150,
    .width = 400,
    .height = 300,
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
    std.debug.print("Shoot!", .{});
    return raylib.IsKeyPressed(raylib.KEY_SPACE);
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
        return raylib.Vector2{ .x = sin, .y = cos };
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

const Asteroid = struct {
    transform: Transform2D,
    size: f32,

    pub fn draw(self: *const Asteroid) void {
        raylib.DrawCircleLinesV(self.transform.position, self.size, raylib.GRAY);
    }

    pub fn checkForDelete(self: *Asteroid, camera: *Camera2D) bool {
        const vectorToCam = raylib.Vector2Subtract(camera.offset, self.transform.position);
        const distToCam = raylib.Vector2Length(vectorToCam);
        if (distToCam >= KILL_RADIUS) {
            return true;
        }
        return false;
    }

    pub fn updatePosition(self: *Asteroid, dt: f32) void {
        // Apply Velocity
        self.transform.position.x += self.transform.velocity.x * dt;
        self.transform.position.y += self.transform.velocity.y * dt;
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

pub fn UpdatePlayer(dt: f32, ship: *Spaceship) void {
    if (isTurnLeft()) {
        ship.transform.rotation -= ROTATION_SPEED * dt;
    }
    if (isTurnRight()) {
        ship.transform.rotation += ROTATION_SPEED * dt;
    }
    if (isThrusterOn()) {
        const forward = ship.transform.forward();
        const thrust = raylib.Vector2{
            .x = forward.x * THRUST_STRENGTH * dt,
            .y = forward.y * THRUST_STRENGTH * dt,
        };

        ship.transform.velocity.x += thrust.x;
        ship.transform.velocity.y -= thrust.y;
    }
    // Apply Velocity
    ship.transform.position.x += ship.transform.velocity.x * dt;
    ship.transform.position.y += ship.transform.velocity.y * dt;
    // Thrust decay
    ship.transform.velocity.x *= 0.999;
    ship.transform.velocity.y *= 0.999;
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

fn rotateVector(v: raylib.Vector2, angle: f32) raylib.Vector2 {
    return raylib.Vector2{
        .x = v.x * @cos(angle) - v.y * @sin(angle),
        .y = v.x * @sin(angle) + v.y * @cos(angle),
    };
}

pub fn GetNewAsteroid(rng: *const std.Random, cam: *Camera2D) Asteroid {
    var spawnFrom = raylib.Vector2{ .x = rng.float(f32), .y = rng.float(f32) };
    spawnFrom = raylib.Vector2Normalize(spawnFrom);
    spawnFrom = raylib.Vector2Add(
        cam.offset,
        raylib.Vector2Multiply(spawnFrom, raylib.Vector2{ .x = SPAWN_RADIUS, .y = SPAWN_RADIUS }),
    );

    const angle = rng.float(f32) * std.math.pi - (std.math.pi / 2.0); // ±90°
    const inverted = raylib.Vector2{ .x = spawnFrom.x * -1, .y = spawnFrom.y * -1 };
    const direction = rotateVector(inverted, angle);
    const velocity = raylib.Vector2{ .x = direction.x, .y = direction.y };

    if (DEBUG) {
        std.debug.print(
            "Spawning asteroid at ({d:.2}, {d:.2}) heading toward ({d:.2}, {d:.2})\n",
            .{ spawnFrom.x, spawnFrom.y, velocity.x, velocity.y },
        );
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

    while (!raylib.WindowShouldClose()) {
        raylib.BeginDrawing();
        raylib.ClearBackground(raylib.BLACK);

        //Update
        const dt = raylib.GetFrameTime();
        UpdatePlayer(dt, &ship);
        UpdateCamera(&camera, ship.transform.position);

        var i: usize = asteroids.items.len;
        while (i > 0) {
            i -= 1;
            var asteroid = asteroids.items[i];
            if (asteroid.checkForDelete(&camera) == true) {
                // allocator.destroy(Asteroid);
                _ = asteroids.swapRemove(i);
            } else {
                asteroid.updatePosition(dt);
            }
        }
        try asteroids.append(GetNewAsteroid(&rand, &camera));

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

            raylib.DrawText(formatted.ptr, @intFromFloat(0), @intFromFloat(0), 20, raylib.GRAY);
            raylib.DrawText(num_asteroids.ptr, @intFromFloat(0), @intFromFloat(25), 20, raylib.GRAY);
        }
        // (Optional) draw UI / HUD here (in screen space)

        raylib.EndDrawing();
    }
}
