const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const sin = std.math.sin;
const cos = std.math.cos;
const assert = std.debug.assert;

const cell_size = 32;
const cells_width = 16.0;
const cells_height = 9.0;
const world_width = cells_width * cell_size;
const world_height = cells_height * cell_size;

const bg_color = rl.Color.init(0x20, 0x2e, 0x37, 0xFF);
const highlight_color = rl.Color.init(0x57, 0x72, 0x77, 0xFF);

const debug = false;
const edit = debug and false;

var screen_width: i32 = 1280;
var screen_height: i32 = 720;

// TODO: ideas for the future (after hackathon)
// "Heat system" (shooting lazers increases heat, heat decreases over time, if heat is too high, CPU throttles)
// "Cooling system" some way to have CPUs that are more resistant to heat

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.setConfigFlags(.{ .window_resizable = false, .window_highdpi = true });
    rl.initWindow(screen_width, screen_height, "Hackathon");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    var game = Game.init();
    defer game.deinit();

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.caps_lock);
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        game.process();
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        game.render();
        //----------------------------------------------------------------------------------
    }
}

/// Gets the mouse position, scaled by camera zoom and clamped to fix issues on MacOS
fn getMousePos(camera: *const rl.Camera2D) rl.Vector2 {
    const msp = rl.getMousePosition().scale(1 / camera.zoom);

    return .{
        .x = @max(msp.x, 0),
        .y = @max(msp.y, 0),
    };
}

fn textureButtonScaled(game: *Game, camera: *const rl.Camera2D, texture: rl.Texture2D, pos: rl.Vector2, rotation: f32, scale: f32) bool {
    const msp = getMousePos(camera);

    const rect = rl.Rectangle.init(pos.x, pos.y, cell_size * scale, cell_size * scale);
    const ms_rect = rl.Rectangle.init(msp.x, msp.y, 1, 1);
    const hovered = rect.checkCollision(ms_rect);
    const clicked = hovered and rl.isMouseButtonPressed(.left);
    const offset: f32 = if (hovered) 1 else 0;

    rl.drawTexturePro(
        texture,
        .{ .x = offset * cell_size, .y = 0, .width = cell_size, .height = cell_size },
        rect,
        rl.Vector2.zero(),
        rotation,
        rl.Color.white,
    );

    if (clicked) {
        rl.playSound(game.sound_map.get(.button_click).?);
    }

    return clicked;
}

fn labelButton(
    game: *Game,
    camera: *const rl.Camera2D,
    text: [:0]const u8,
    rect: rl.Rectangle,
    opt: struct {
        font: rl.Font,
        font_size: f32,
        spacing: f32,
        text_color: rl.Color = rl.Color.white,
    },
) bool {
    const msp = getMousePos(camera);
    const texture = game.texture_map.get(.button).?;

    const ms_rect = rl.Rectangle.init(msp.x, msp.y, 1, 1);
    const hovered = rect.checkCollision(ms_rect);
    const mouse_down = rl.isMouseButtonDown(.left);
    const clicked = hovered and rl.isMouseButtonReleased(.left);
    const offset: f32 = if (mouse_down) 2 else if (hovered) 1 else 0;

    assert(rect.width >= cell_size * 2); // Button needs at least 2 cells!
    assert(@mod(rect.width, cell_size) == 0); // Needs to be a multiple of cell size
    assert(rect.height == cell_size); // Needs to be a single row

    rl.drawTexturePro(
        texture,
        .{ .x = cell_size * 3 * offset, .y = 0, .width = cell_size, .height = cell_size },
        .{ .x = rect.x, .y = rect.y, .width = cell_size, .height = rect.height },
        rl.Vector2.zero(),
        0,
        rl.Color.white,
    );
    rl.drawTexturePro(
        texture,
        .{ .x = cell_size * 3 * offset + cell_size, .y = 0, .width = cell_size, .height = cell_size },
        .{ .x = rect.x + cell_size, .y = rect.y, .width = rect.width - cell_size, .height = rect.height },
        rl.Vector2.zero(),
        0,
        rl.Color.white,
    );
    rl.drawTexturePro(
        texture,
        .{ .x = cell_size * 3 * offset + (cell_size * 2), .y = 0, .width = cell_size, .height = cell_size },
        .{ .x = rect.x + rect.width - cell_size, .y = rect.y, .width = cell_size, .height = rect.height },
        rl.Vector2.zero(),
        0,
        rl.Color.white,
    );

    const text_vec = rl.measureTextEx(opt.font, text, opt.font_size, opt.spacing);
    rl.drawTextEx(
        opt.font,
        text,
        rl.Vector2.init(rect.x + ((rect.width - text_vec.x) / 2), rect.y + ((rect.height - text_vec.y) / 2)),
        opt.font_size,
        opt.spacing,
        opt.text_color,
    );

    if (mouse_down) {
        rl.playSound(game.sound_map.get(.button_click).?);
    }

    return clicked;
}

const BugKind = enum(u8) {
    nullptr_deref = 0,
    stack_overflow = 1,
    infinite_loop = 2,

    const count = @typeInfo(BugKind).@"enum".fields.len;
};

const Bug = struct {
    kind: BugKind,
    health: f32,
    position: rl.Vector2,
    previous: rl.Vector2, // Center of prev
    target: rl.Vector2, // Center of next cell
    animation_time: f32 = 0,
    animation_state: f32 = 0,
    prev_angle: f32 = 0,
    angle: f32 = 0,
    dead: bool = false,

    pub fn init(kind: BugKind, position: rl.Vector2) Bug {
        return Bug{
            .kind = kind,
            .health = maxHealth(kind),
            .position = position,
            .previous = position,
            .target = position.add(rl.Vector2.init(cell_size, 0)), // 1 unit to the right
        };
    }

    pub fn update(self: *Bug, delta_time: f32, wave: *Wave, ram: *f32, game: *Game) void {
        self.animation_time += delta_time;
        if (self.animation_time > animationSwitchThreshold(self.kind)) {
            self.animation_time = 0;
            self.animation_state = @mod((self.animation_state + 1), animationCount(self.kind));
        }

        var velocity: rl.Vector2 = self.target.subtract(self.position);
        velocity = velocity.normalize().scale(speed(self.kind));
        self.position = self.position.add(velocity);

        const prev_grid_x: usize = @intFromFloat(self.previous.x / cell_size);
        const prev_grid_y: usize = @intFromFloat(self.previous.y / cell_size);
        const grid_x: usize = @intFromFloat(self.position.x / cell_size);
        const grid_y: usize = @intFromFloat(self.position.y / cell_size);
        const target_grid_x: usize = @intFromFloat(self.target.x / cell_size);
        const target_grid_y: usize = @intFromFloat(self.target.y / cell_size);

        const c_lane_left = wave.get(grid_x -| 1, grid_y).isLaneConnected();
        const c_lane_right = wave.get(grid_x + 1, grid_y).isLaneConnected();
        const c_lane_top = wave.get(grid_x, grid_y -| 1).isLaneConnected();
        const c_lane_bottom = wave.get(grid_x, grid_y + 1).isLaneConnected();

        const matching = grid_x == target_grid_x and grid_y == target_grid_y;
        const prev_angle = self.prev_angle;

        // For animation rotation
        var desired_angle_delta: f32 = 0.0;
        if (c_lane_left and c_lane_bottom and !matching) {
            desired_angle_delta = 90;
        } else if (c_lane_right and c_lane_top and !matching) {
            desired_angle_delta = -90;
        } else if (c_lane_left and c_lane_top and !matching) {
            desired_angle_delta = -90;
        } else if (c_lane_right and c_lane_bottom and !matching) {
            desired_angle_delta = 90;
        }

        const distance = cell_size / 2;
        // const t = if (matching)
        //     self.position.distance(self.target) / distance
        // else
        //     self.position.distance(self.previous) / distance;
        const t = self.position.distance(self.previous) / distance;

        const desired_angle = prev_angle + desired_angle_delta;
        if (desired_angle_delta != 0) {
            // self.angle = rl.math.lerp(@min(prev_angle, desired_angle), @max(prev_angle, desired_angle), t);
            self.angle = rl.math.lerp(prev_angle, desired_angle, t);

            if (t > 0.99) {
                // self.prev_angle = self.angle;
                self.prev_angle = @round(self.angle / 90.0) * 90.0;
            }

            std.debug.print("------------------------\n", .{});
            std.debug.print("angle: {d}\n", .{self.angle});
            std.debug.print("t: {d}\n", .{t});
            std.debug.print("desired_angle_delta: {d}\n", .{desired_angle_delta});
            std.debug.print("desired_angle: {d}\n", .{desired_angle});
            std.debug.print("prev_angle: {d}\n", .{prev_angle});
            std.debug.print("self.prev_angle: {d}\n", .{self.prev_angle});
        }

        // 1 is 1/32th of a cell
        if (self.position.distanceSqr(self.target) < 1) {
            // Find new target

            const t_lane_left = wave.get(target_grid_x - 1, target_grid_y).isLaneConnected();
            const t_lane_right = wave.get(target_grid_x + 1, target_grid_y).isLaneConnected();
            const t_lane_top = wave.get(target_grid_x, target_grid_y - 1).isLaneConnected();
            const t_lane_bottom = wave.get(target_grid_x, target_grid_y + 1).isLaneConnected();

            var target: rl.Vector2 = rl.Vector2.init(0, 0);
            if (t_lane_left and prev_grid_x != target_grid_x - 1) {
                target = self.target.add(rl.Vector2.init(-cell_size, 0));
                std.debug.print("lane left\n", .{});
            }
            if (t_lane_right and prev_grid_x != target_grid_x + 1) {
                target = self.target.add(rl.Vector2.init(cell_size, 0));
                std.debug.print("lane right\n", .{});
            }
            if (t_lane_top and prev_grid_y != target_grid_y - 1) {
                target = self.target.add(rl.Vector2.init(0, -cell_size));
                std.debug.print("lane top\n", .{});
            }
            if (t_lane_bottom and prev_grid_y != target_grid_y + 1) {
                target = self.target.add(rl.Vector2.init(0, cell_size));
                std.debug.print("lane bottom\n", .{});
            }
            if (target.x == 0 and target.y == 0) {
                if (wave.get(target_grid_x, target_grid_y) == .ram) {
                    self.dead = true;
                    const prev_ram_percentage = ram.* / ScreenBattle.max_ram;
                    ram.* = @max(ram.* - self.memory(), 0);
                    const ram_percentage = ram.* / ScreenBattle.max_ram;

                    const is_75 = prev_ram_percentage > 0.75 and ram_percentage <= 0.75;
                    const is_50 = prev_ram_percentage > 0.5 and ram_percentage <= 0.5;
                    const is_25 = prev_ram_percentage > 0.25 and ram_percentage <= 0.25;
                    const is_0 = prev_ram_percentage > 0 and ram_percentage <= 0;
                    if (is_75 or is_50 or is_25 or is_0) {
                        rl.playSound(game.sound_map.get(.ram_destroyed).?);
                    } else {
                        rl.playSound(game.sound_map.get(.bug_attack).?);
                    }
                } else {
                    unreachable;
                }
            }

            self.previous = self.target;
            self.target = target;
        }
    }

    fn transistors(bug: Bug) u32 {
        return switch (bug.kind) {
            .nullptr_deref => return 10,
            .stack_overflow => return 20,
            .infinite_loop => return 5,
        };
    }

    pub fn maxHealth(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 2,
            .stack_overflow => return 10,
            .infinite_loop => return 0.5,
        };
    }

    fn speed(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 0.5,
            .stack_overflow => return 0.1,
            .infinite_loop => return 4,
        };
    }

    fn damage(self: *Bug, dmg: f32) bool {
        self.health -= dmg;
        if (self.health <= 0) {
            self.dead = true;
        }
        return self.dead;
    }

    fn memory(self: Bug) f32 {
        return switch (self.kind) {
            .nullptr_deref => return 10,
            .stack_overflow => return 20,
            .infinite_loop => return 6,
            // .nullptr_deref => return 1,
            // .stack_overflow => return 2,
            // .infinite_loop => return 0.5,
        } * self.health;
    }

    fn animationCount(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 2,
            .stack_overflow => return 2,
            .infinite_loop => return 6,
        };
    }

    fn animationSwitchThreshold(kind: BugKind) f32 {
        return (1 / speed(kind)) / (animationCount(kind) * 3);
        // return switch (kind) {
        //     .nullptr_deref => return 0.3,
        //     .stack_overflow => return 0.3,
        //     .infinite_loop => return 0.05,
        // };
    }
};

const Instruction = struct {
    condition: Condition = .always,
    opcode: Opcode = .noop,

    const Condition = union(enum) {
        always,
        memory_leak: f32, // Health percentage, ram<0.25 or ram<0.5 (randomized)
        bug: BugKind, // Against this specific enemy type
        idle: f32, // Idle time in seconds, 1s-2s (randomized)
    };

    const Opcode = union(enum) {
        noop, // does nothing
        sleep: f32, // Slows enemies (multiplier of enemy speed, 0.5-0.9 randomized)
        prefetch: f32, // Larger radius (multiplier of cache size, 1.5-2 randomized)
        overclock: f32, // Deals more damage (multiplier of bus width, 1.5-2 randomized)
        // // overclock: f32, // Faster firerate (multiplier of clock speed, 1.1-1.5 randomized)
    };
};

const Cpu = struct {
    // clock_speed: f32 = 1, // Fire rate, every how many seconds to fire
    bus_width: f32 = 1, // Bus width, damage dealt
    cache_size: f32 = 1.5, // Cache size, range (distance for attack)
    debugs: u32 = 0, // How many bugs were killed
    instructions: [max_instructions]Instruction = [_]Instruction{.{}} ** max_instructions, // modifiers
    upgrades: u32 = 1, // TODO: remove this after hackathon, for a better instruction system

    const max_instructions = 5;

    fn damage(self: Cpu) f32 {
        return self.bus_width;
    }

    fn cores(self: Cpu) u32 {
        return switch (self.level()) {
            1 => 1,
            2 => 2,
            3 => 4,
            4 => 8,
            else => 16,
        };
    }

    fn level(self: Cpu) u32 {
        return switch (self.debugs) {
            // TODO: only for debug (change this once ready for play testing)
            // 0...2 => 1,
            // 3...4 => 2,
            // 5...6 => 3,
            // 7...8 => 4,
            // else => 5,
            0...9 => 1,
            10...24 => 2,
            25...49 => 3,
            50...100 => 4,
            else => 5,
        };
    }

    fn upgradeBusWidth(self: *Cpu) bool {
        if (self.upgrades < self.level()) {
            self.upgrades += 1;
            self.bus_width += 1;
            return true;
        }
        return false;
    }

    fn upgradeCacheSize(self: *Cpu) bool {
        if (self.upgrades < self.level()) {
            self.upgrades += 1;
            self.cache_size += 0.5;
            return true;
        }
        return false;
    }

    fn hasUpgrades(self: Cpu) bool {
        return self.upgrades < self.level();
    }
};

const Cell = union(enum) {
    none,
    socket,
    cpu: Cpu,
    ai,
    ram,
    lane,

    fn isLaneConnected(self: Cell) bool {
        return switch (self) {
            .lane => true,
            .ai => true,
            .ram => true,
            else => false,
        };
    }
};

const SpawnRule = struct {
    from_time_s: f32,
    to_time_s: f32,
    bugs: [BugKind.count]struct {
        last_spawn: f32 = 0,
        spawn_interval: f32,
    }, // index is enum
};

const Wave = struct {
    arena: std.heap.ArenaAllocator,
    map: [cells_height][cells_width]Cell = [_][cells_width]Cell{[_]Cell{.none} ** cells_width} ** cells_height,
    bugs: std.ArrayList(Bug),
    spawn_rules: std.ArrayList(SpawnRule),
    time_since_start: f32 = 0,

    fn init(wave_number: u8) Wave {
        const height_middle = 4;

        // TODO: probably fine for hackathon but post hackathon, this is really bad
        // We alloc 2 arraylists on this, we need a pool allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

        // This is horrible code, sorry
        var spawn_rules = std.ArrayList(SpawnRule).init(arena.allocator());
        var map: [cells_height][cells_width]Cell = undefined;
        if (wave_number == 1) {
            map = [_][cells_width]Cell{
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .socket, .lane, .lane, .lane, .socket, .none, .none, .none, .none, .none, .none },
                .{ .none, .socket, .socket, .socket, .socket, .socket, .lane, .socket, .lane, .socket, .socket, .socket, .socket, .socket, .socket, .none },
                .{ .ai, .lane, .lane, .lane, .lane, .socket, .lane, .socket, .lane, .lane, .lane, .lane, .lane, .lane, .lane, .ram },
                .{ .none, .socket, .socket, .socket, .lane, .socket, .lane, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .none },
                .{ .none, .none, .none, .socket, .lane, .lane, .lane, .socket, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
            };

            // spawn_rules.append(.{
            //     .from_time_s = 0,
            //     .to_time_s = 1.1,
            //     .bugs = .{
            //         // .{ .spawn_interval = 0.5 },
            //         // .{ .spawn_interval = 0.5 },
            //         // .{ .spawn_interval = 0.5 },
            //         .{ .spawn_interval = 0 },
            //         .{ .spawn_interval = 0 },
            //         .{ .spawn_interval = 0 },
            //     },
            // }) catch unreachable;

            // TODO: game design MARK
            spawn_rules.append(.{
                .from_time_s = 0,
                .to_time_s = 4,
                .bugs = .{
                    .{ .spawn_interval = 3 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 7,
                .to_time_s = 20,
                .bugs = .{
                    .{ .spawn_interval = 2.5 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 24,
                .to_time_s = 32,
                .bugs = .{
                    .{ .spawn_interval = 2 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 35,
                .to_time_s = 36.1,
                .bugs = .{
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 1 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 40,
                .to_time_s = 65,
                .bugs = .{
                    .{ .spawn_interval = 1.2 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 60,
                .to_time_s = 60.15,
                .bugs = .{
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0.1 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 60,
                .to_time_s = 71,
                .bugs = .{
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 2 },
                },
            }) catch unreachable;

            spawn_rules.append(.{
                .from_time_s = 65,
                .to_time_s = 75,
                .bugs = .{
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 4 },
                    .{ .spawn_interval = 0 },
                },
            }) catch unreachable;
        } else if (wave_number == 2) {
            // TODO: game design
            spawn_rules.append(.{
                .from_time_s = 0,
                .to_time_s = 30,
                .bugs = .{
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
                },
            }) catch unreachable;

            map = .{
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .socket, .lane, .lane, .lane, .lane, .lane, .socket, .none, .none, .none, .none, .none, .none },
                .{ .none, .socket, .socket, .socket, .lane, .socket, .socket, .socket, .lane, .socket, .socket, .socket, .socket, .socket, .socket, .none },
                .{ .ai, .lane, .lane, .lane, .lane, .socket, .lane, .lane, .lane, .socket, .lane, .lane, .lane, .lane, .lane, .ram },
                .{ .none, .socket, .socket, .socket, .socket, .socket, .lane, .socket, .socket, .socket, .lane, .socket, .socket, .socket, .socket, .none },
                .{ .none, .none, .none, .none, .none, .socket, .lane, .lane, .lane, .lane, .lane, .socket, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
            };
        } else if (wave_number == 3) {
            // TODO: game design
            spawn_rules.append(.{
                .from_time_s = 0,
                .to_time_s = 30,
                .bugs = .{
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
                },
            }) catch unreachable;

            map = .{
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none, .none, .none, .socket, .socket, .socket, .none },
                .{ .ai, .lane, .lane, .lane, .lane, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .lane, .lane, .ram },
                .{ .none, .socket, .socket, .socket, .lane, .socket, .socket, .lane, .lane, .lane, .lane, .lane, .socket, .lane, .socket, .none },
                .{ .none, .none, .none, .socket, .lane, .lane, .lane, .lane, .socket, .socket, .socket, .lane, .lane, .lane, .socket, .none },
                .{ .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .socket, .none, .socket, .socket, .socket, .socket, .socket, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
            };
        } else {
            unreachable;
        }

        var wave = Wave{
            .arena = arena,
            .bugs = std.ArrayList(Bug).init(arena.allocator()),
            .spawn_rules = spawn_rules,
            .map = map,
        };

        wave.map[height_middle][0] = .ai;
        wave.map[height_middle][cells_width - 1] = .ram;

        return wave;
    }

    fn update(self: *Wave, delta_time: f32, ram: *f32, game: *Game) bool {
        // TODO: quite a bit of logic here
        self.time_since_start += delta_time;

        const half_cell = cell_size / 2;
        const ai_position = rl.Vector2.init(half_cell, 4 * cell_size + half_cell);

        var wave_over = true;

        // TODO: post hackathon, optimize this
        for (self.spawn_rules.items) |*rules| {
            if (rules.to_time_s < self.time_since_start) {
                continue;
            }
            wave_over = false;
            if (rules.from_time_s > self.time_since_start) {
                continue;
            }

            for (0..rules.bugs.len) |i| {
                if (rules.bugs[i].spawn_interval == 0) {
                    continue;
                }

                rules.bugs[i].last_spawn += delta_time;
                if (rules.bugs[i].last_spawn >= rules.bugs[i].spawn_interval) {
                    rules.bugs[i].last_spawn -= rules.bugs[i].spawn_interval;
                    self.bugs.append(Bug.init(@enumFromInt(i), ai_position)) catch unreachable;
                }
            }
        }

        for (self.bugs.items) |*bug| {
            if (bug.dead) {
                continue;
            }
            wave_over = false;
            bug.update(delta_time, self, ram, game);
        }

        return wave_over;
    }

    fn deinit(self: *Wave) void {
        self.arena.deinit();
    }

    fn at(self: *Wave, x: usize, y: usize) ?*Cell {
        if (x >= cells_width or y >= cells_height or x < 0 or y < 0) {
            return null;
        }
        return &self.map[y][x];
    }

    fn get(self: *Wave, x: usize, y: usize) Cell {
        if (x >= cells_width or y >= cells_height or x < 0 or y < 0) {
            return .none;
        }
        return self.map[y][x];
    }

    fn set(self: *Wave, x: usize, y: usize, cell: Cell) void {
        if (x < cells_width and y < cells_height and x >= 0 and y >= 0) {
            self.map[y][x] = cell;
        }
    }
};

const TextureKind = enum {
    cpus_vs_bugs,
    power_button,
    socket,
    lane,
    ai,
    cpu,
    ram,
    bug_null,
    bug_while,
    bug_stackoverflow,
    transistor,
    cpu_pins,
    upgrade_popup,
    button,
};

const SoundKind = enum {
    bug_death,
    bug_attack,
    ram_destroyed,
    cpu_place,
    cpu_upgrade,
    button_click,
};

const Game = struct {
    global_arena: std.heap.ArenaAllocator,
    frame_arena: std.heap.ArenaAllocator,

    texture_map: std.AutoHashMap(TextureKind, rl.Texture2D),
    sound_map: std.AutoHashMap(SoundKind, rl.Sound),

    font_title: rl.Font,
    font_normal: rl.Font,

    screen_state: union(enum) {
        main: ScreenMainMenu,
        battle: ScreenBattle,
        gameover: ScreenGameOver,
        victory: ScreenVictory,
    },

    fn init() Game {
        var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const ga = global_arena.allocator();
        var texture_map = std.AutoHashMap(TextureKind, rl.Texture2D).init(ga);
        var sound_map = std.AutoHashMap(SoundKind, rl.Sound).init(ga);

        // TODO: make this texture loading more dynamic - DO THIS AFTER JAM
        const cpus_vs_bugs = rl.loadTexture("assets/img/cpus-vs-bugs.png") catch unreachable;
        const power_button = rl.loadTexture("assets/img/power-button.png") catch unreachable;
        const lane = rl.loadTexture("assets/img/lane.png") catch unreachable;
        const socket = rl.loadTexture("assets/img/socket.png") catch unreachable;
        const ai = rl.loadTexture("assets/img/ai.png") catch unreachable;
        const bug_so = rl.loadTexture("assets/img/stackoverflow.png") catch unreachable;
        const bug_null = rl.loadTexture("assets/img/nullptr-deref.png") catch unreachable;
        const bug_while = rl.loadTexture("assets/img/while1.png") catch unreachable;
        const ram = rl.loadTexture("assets/img/ram.png") catch unreachable;
        const transistor = rl.loadTexture("assets/img/transistor.png") catch unreachable;
        const cpu_pins = rl.loadTexture("assets/img/cpu_pins.png") catch unreachable;
        const cpu = rl.loadTexture("assets/img/cpu.png") catch unreachable;
        const upgrade_popup = rl.loadTexture("assets/img/upgrade-popup.png") catch unreachable;
        const button = rl.loadTexture("assets/img/button.png") catch unreachable;
        texture_map.put(.cpus_vs_bugs, cpus_vs_bugs) catch unreachable;
        texture_map.put(.power_button, power_button) catch unreachable;
        texture_map.put(.socket, socket) catch unreachable;
        texture_map.put(.lane, lane) catch unreachable;
        texture_map.put(.ai, ai) catch unreachable;
        texture_map.put(.bug_null, bug_null) catch unreachable;
        texture_map.put(.bug_stackoverflow, bug_so) catch unreachable;
        texture_map.put(.bug_while, bug_while) catch unreachable;
        texture_map.put(.ram, ram) catch unreachable;
        texture_map.put(.transistor, transistor) catch unreachable;
        texture_map.put(.cpu_pins, cpu_pins) catch unreachable;
        texture_map.put(.cpu, cpu) catch unreachable;
        texture_map.put(.upgrade_popup, upgrade_popup) catch unreachable;
        texture_map.put(.button, button) catch unreachable;

        const bug_death = rl.loadSound("assets/sfx/bug-death.wav") catch unreachable;
        rl.setSoundVolume(bug_death, 0.3);
        const bug_attack = rl.loadSound("assets/sfx/bug-attack.wav") catch unreachable;
        rl.setSoundVolume(bug_attack, 0.5);
        const ram_destroyed = rl.loadSound("assets/sfx/ram-destroyed.wav") catch unreachable;
        rl.setSoundVolume(ram_destroyed, 0.8);
        const cpu_place = rl.loadSound("assets/sfx/cpu-place.mp3") catch unreachable;
        rl.setSoundVolume(cpu_place, 0.8);
        const cpu_upgrade = rl.loadSound("assets/sfx/cpu-upgrade.wav") catch unreachable;
        rl.setSoundVolume(cpu_upgrade, 0.8);
        const button_click = rl.loadSound("assets/sfx/button-click.mp3") catch unreachable;
        rl.setSoundVolume(button_click, 0.5);
        sound_map.put(.bug_death, bug_death) catch unreachable;
        sound_map.put(.bug_attack, bug_attack) catch unreachable;
        sound_map.put(.ram_destroyed, ram_destroyed) catch unreachable;
        sound_map.put(.cpu_place, cpu_place) catch unreachable;
        sound_map.put(.cpu_upgrade, cpu_upgrade) catch unreachable;
        sound_map.put(.button_click, button_click) catch unreachable;

        const font_title = rl.loadFontEx("assets/font/DepartureMonoNerdFontMono-Regular.otf", 80, null) catch unreachable;
        const font_normal = rl.loadFontEx("assets/font/GohuFont14NerdFontMono-Regular.ttf", 80, null) catch unreachable;

        return .{
            .global_arena = global_arena,
            .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .texture_map = texture_map,
            .sound_map = sound_map,
            .font_title = font_title,
            .font_normal = font_normal,
            .screen_state = .{
                // .main = .init(), // MARK
                // .gameover = .init(),
                // .victory = .init(),
                .battle = .init(),
            },
        };
    }

    fn deinit(self: *Game) void {
        self.global_arena.deinit();
        self.frame_arena.deinit();
    }

    fn frameStart(self: *Game) void {
        const reset_successful = self.frame_arena.reset(.retain_capacity);
        assert(reset_successful);
    }

    fn process(self: *Game) void {
        const dt = rl.getFrameTime();

        // std.debug.print("Delta time: {d}\n", .{dt});

        // TODO: find a better method of mutating the original
        switch (self.screen_state) {
            .main => {
                self.screen_state.main.update(self, dt);
            },
            .battle => {
                self.screen_state.battle.update(self, dt);
            },
            .gameover => {
                self.screen_state.gameover.update(self, dt);
            },
            .victory => {
                self.screen_state.victory.update(self, dt);
            },
        }
    }

    fn render(self: *Game) void {
        rl.beginDrawing();
        defer rl.endDrawing();

        // TODO: maybe add a system for each screen to be able to give a color to set the background?
        // just so the render method of the screens doesn't have to directly call rl.clearBackground
        rl.clearBackground(bg_color);

        // TODO: find a better method of mutating the original
        switch (self.screen_state) {
            .main => {
                self.screen_state.main.render(self);
            },
            .battle => {
                self.screen_state.battle.render(self);
            },
            .gameover => {
                self.screen_state.gameover.render(self);
            },
            .victory => {
                self.screen_state.victory.render(self);
            },
        }
    }
};

const ScreenMainMenu = struct {
    camera: rl.Camera2D,
    pressed_start: bool = false,

    const start_button_scaling = 5;
    const start_button_size: f32 = @floatFromInt(cell_size * start_button_scaling);
    const title_size: f32 = @floatFromInt(cell_size * 5);

    fn init() ScreenMainMenu {
        return .{
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screen_width)) / 2,
                    .y = @as(f32, @floatFromInt(screen_height)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screen_height)) / world_height,
            },
        };
    }

    fn update(self: *ScreenMainMenu, game: *Game, dt: f32) void {
        _ = dt;

        self.updateCamera();

        if (self.pressed_start) {
            game.screen_state = .{ .battle = .init() };
        }
    }

    fn render(self: *ScreenMainMenu, game: *Game) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();

        const scaling_factor = 2;
        const title_pos: rl.Vector2 = .{
            .x = (world_width - (ScreenMainMenu.title_size * scaling_factor)) / 2,
            .y = cell_size / 2, // padding
        };

        rl.drawTexturePro(
            game.texture_map.get(.cpus_vs_bugs).?,
            .{
                .x = 0,
                .y = 0,
                .width = ScreenMainMenu.title_size,
                .height = cell_size,
            },
            .{
                .x = title_pos.x,
                .y = title_pos.y,
                .width = ScreenMainMenu.title_size * scaling_factor,
                .height = cell_size * scaling_factor,
            },
            rl.Vector2.zero(),
            0,
            rl.Color.white,
        );

        const padding = cell_size + cell_size / 2;
        self.pressed_start = textureButtonScaled(
            game,
            &self.camera,
            game.texture_map.get(.power_button).?,
            rl.Vector2.init(
                (world_width - ScreenMainMenu.start_button_size) / 2,
                (world_height - ScreenMainMenu.start_button_size) / 2 + padding,
            ),
            0,
            ScreenMainMenu.start_button_scaling,
        );
    }

    fn updateCamera(self: *ScreenMainMenu) void {
        screen_width = rl.getScreenWidth();
        screen_height = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screen_width)) / 2,
            .y = @as(f32, @floatFromInt(screen_height)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screen_width)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screen_height)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }
};

const ScreenGameOver = struct {
    camera: rl.Camera2D,
    pressed_retry: bool = false,
    pressed_menu: bool = false,
    dt: f32 = -1.0,
    game_over_text: [:0]const u8 = "Game Over",
    game_over_size: f32 = 22,
    game_over_spacing: f32 = 1.0,
    game_over_color: rl.Color = rl.Color.red,
    game_over_measurement: rl.Vector2 = .{ .x = 0, .y = 0 },
    game_over_widths: [9]f32 = undefined,
    game_over_height: f32 = 0,
    game_over_speed: f32 = 2.0,
    game_over_animation_offset: f32 = 0.2,
    game_over_animation_size: f32 = 0.3,
    initiated: bool = false,

    const button_menu_width: f32 = @floatFromInt(cell_size * 7);
    const button_menu_height: f32 = @floatFromInt(cell_size);

    fn init() ScreenGameOver {
        return .{
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screen_width)) / 2,
                    .y = @as(f32, @floatFromInt(screen_height)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screen_height)) / world_height,
            },
        };
    }

    fn update(self: *ScreenGameOver, game: *Game, dt: f32) void {
        if (self.initiated) {
            self.dt += dt;
        }

        self.updateCamera();

        // Must be the last thing
        if (self.pressed_retry) {
            game.screen_state = .{ .battle = .init() };
        } else if (self.pressed_menu) {
            game.screen_state = .{ .main = .init() };
        }
    }

    fn updateCamera(self: *ScreenGameOver) void {
        screen_width = rl.getScreenWidth();
        screen_height = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screen_width)) / 2,
            .y = @as(f32, @floatFromInt(screen_height)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screen_width)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screen_height)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }

    fn render(self: *ScreenGameOver, game: *Game) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();

        if (!self.initiated) {
            var i: usize = 0;
            const len: usize = self.game_over_text.len;
            if (len != self.game_over_widths.len) {
                std.log.err("Game over text length isn't covered properly. adjust ScreenGameOver.game_over_widths and ScreenGameOver.game_over_characters accordingly to {} instead of {}", .{ len, self.game_over_widths.len });
                return;
            }
            while (i < len) : (i += 1) {
                const substring = self.game_over_text[i..];
                const measurement = rl.measureTextEx(game.font_title, substring, self.game_over_size, self.game_over_spacing);
                if (i == 0) {
                    self.game_over_height = measurement.y;
                }
                self.game_over_widths[i] = measurement.x;
            }
            self.initiated = true;
        }

        // total width and height for the game over text
        const tx = self.game_over_widths[0];
        const ty = self.game_over_height;

        // we have widths for the title with the start chopped off.
        // let's calculate the right side
        const rx = (world_width + tx) / 2;
        const ry = (world_height - ty) / 2;
        var i: usize = 0;
        const len: usize = self.game_over_text.len;
        while (i < len) {
            const fi: f32 = @as(f32, @floatFromInt(i));
            const width = self.game_over_widths[i];
            const x = rx - width;
            // feel free to find a better way to extract single characters:
            const char = rl.textFormat("%c", .{self.game_over_text[i]});
            const y = ry - ty * self.game_over_animation_size * sin((self.dt + self.game_over_animation_offset * fi) * self.game_over_speed);
            rl.drawTextEx(game.font_title, char, .{ .x = x, .y = y }, self.game_over_size, self.game_over_spacing, self.game_over_color);
            i += 1;
        }

        self.pressed_menu = labelButton(
            game,
            &self.camera,
            "Back to main menu",
            rl.Rectangle.init(
                (world_width - ScreenGameOver.button_menu_width) / 2,
                (world_height - ScreenGameOver.button_menu_height) / 2 + cell_size * 1.25,
                ScreenGameOver.button_menu_width,
                ScreenGameOver.button_menu_height,
            ),
            .{
                .font = game.font_title,
                .font_size = 10,
                .spacing = 5,
            },
        );
        self.pressed_retry = labelButton(
            game,
            &self.camera,
            "Retry",
            rl.Rectangle.init(
                (world_width - ScreenGameOver.button_menu_width) / 2,
                (world_height - ScreenGameOver.button_menu_height) / 2 + cell_size * 2.25,
                ScreenGameOver.button_menu_width,
                ScreenGameOver.button_menu_height,
            ),
            .{
                .font = game.font_title,
                .font_size = 10,
                .spacing = 5,
            },
        );
    }
};

const ScreenVictory = struct {
    camera: rl.Camera2D,
    pressed_play_again: bool = false,
    pressed_menu: bool = false,
    dt: f32 = -1.0,
    text: [:0]const u8 = "You win!",
    size: f32 = 22,
    spacing: f32 = 1.0,
    color: rl.Color = rl.Color.green,
    measurement: rl.Vector2 = .{ .x = 0, .y = 0 },
    widths: [8]f32 = undefined,
    height: f32 = 0,
    speed: f32 = 2.0,
    animation_offset: f32 = 0.2,
    animation_size: f32 = 0.3,
    initiated: bool = false,

    const button_menu_width: f32 = @floatFromInt(cell_size * 7);
    const button_menu_height: f32 = @floatFromInt(cell_size);

    fn init() ScreenVictory {
        return .{
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screen_width)) / 2,
                    .y = @as(f32, @floatFromInt(screen_height)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screen_height)) / world_height,
            },
        };
    }

    fn update(self: *ScreenVictory, game: *Game, dt: f32) void {
        if (self.initiated) {
            self.dt += dt;
        }

        self.updateCamera();

        // Must be the last thing
        if (self.pressed_play_again) {
            game.screen_state = .{ .battle = .init() };
        } else if (self.pressed_menu) {
            game.screen_state = .{ .main = .init() };
        }
    }

    fn updateCamera(self: *ScreenVictory) void {
        screen_width = rl.getScreenWidth();
        screen_height = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screen_width)) / 2,
            .y = @as(f32, @floatFromInt(screen_height)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screen_width)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screen_height)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }

    fn render(self: *ScreenVictory, game: *Game) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();

        if (!self.initiated) {
            var i: usize = 0;
            const len: usize = self.text.len;
            assert(len == self.widths.len);
            while (i < len) : (i += 1) {
                const substring = self.text[i..];
                const measurement = rl.measureTextEx(game.font_title, substring, self.size, self.spacing);
                if (i == 0) {
                    self.height = measurement.y;
                }
                self.widths[i] = measurement.x;
            }
            self.initiated = true;
        }

        // total width and height for the game over text
        const tx = self.widths[0];
        const ty = self.height;

        // we have widths for the title with the start chopped off.
        // let's calculate the right side
        const rx = (world_width + tx) / 2;
        const ry = (world_height - ty) / 2;
        var i: usize = 0;
        const len: usize = self.text.len;
        while (i < len) {
            const fi: f32 = @as(f32, @floatFromInt(i));
            const width = self.widths[i];
            const x = rx - width;
            // feel free to find a better way to extract single characters:
            const char = rl.textFormat("%c", .{self.text[i]});
            const y = ry - ty * self.animation_size * sin((self.dt + self.animation_offset * fi) * self.speed);
            rl.drawTextEx(game.font_title, char, .{ .x = x, .y = y }, self.size, self.spacing, self.color);
            i += 1;
        }

        self.pressed_menu = labelButton(
            game,
            &self.camera,
            "Back to main menu",
            rl.Rectangle.init(
                (world_width - ScreenVictory.button_menu_width) / 2,
                (world_height - ScreenVictory.button_menu_height) / 2 + cell_size * 1.25,
                ScreenVictory.button_menu_width,
                ScreenVictory.button_menu_height,
            ),
            .{
                .font = game.font_title,
                .font_size = 10,
                .spacing = 5,
            },
        );
        self.pressed_play_again = labelButton(
            game,
            &self.camera,
            "Play again",
            rl.Rectangle.init(
                (world_width - ScreenVictory.button_menu_width) / 2,
                (world_height - ScreenVictory.button_menu_height) / 2 + cell_size * 2.25,
                ScreenVictory.button_menu_width,
                ScreenVictory.button_menu_height,
            ),
            .{
                .font = game.font_normal,
                .font_size = 10,
                .spacing = 5,
            },
        );
    }
};

const ScreenBattle = struct {
    camera: rl.Camera2D,
    wave: Wave,
    wave_number: u8,
    ram: f32, // health of the player
    transistors: u32,
    wave_over_timer: f32 = 0,

    popup: bool = false,

    const max_ram = 100;
    const cpu_transistor_cost = 100;
    const wave_continue_delay = 2; // seconds

    fn init() ScreenBattle {
        const wave_number: u8 = 1; // MARK
        return .{
            .wave_number = wave_number,
            .wave = .init(wave_number),
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screen_width)) / 2,
                    .y = @as(f32, @floatFromInt(screen_height)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screen_height)) / world_height,
            },
            .ram = max_ram,
            .transistors = cpu_transistor_cost,
        };
    }

    fn deinit(self: *ScreenBattle) void {
        self.wave.deinit();
    }

    fn update(self: *ScreenBattle, game: *Game, dt: f32) void {
        self.handlePlayerInput(game, dt);

        self.updateCpuAndBugs(game, dt);
        const wave_over = self.wave.update(dt, &self.ram, game);
        if (wave_over) {
            self.wave_over_timer += dt;
        }

        self.updateCamera();

        if (self.ram <= 0) {
            self.deinit();
            game.screen_state = .{ .gameover = .init() };
        } else if (self.wave_over_timer >= wave_continue_delay) {
            self.wave_over_timer = 0;
            self.wave_number += 1;
            self.transistors = cpu_transistor_cost;
            if (self.wave_number > 3) {
                self.deinit();
                game.screen_state = .{ .victory = .init() };
            } else {
                self.wave.deinit();
                self.wave = .init(self.wave_number);
            }
        }
    }

    fn handlePlayerInput(self: *ScreenBattle, game: *Game, dt: f32) void {
        _ = dt;

        const msp = getMousePos(&self.camera);

        const mx: usize = @intFromFloat(msp.x / cell_size);
        const my: usize = @intFromFloat(msp.y / cell_size);

        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            if (self.wave.get(mx, my) == .lane and edit) {
                self.wave.set(mx, my, .socket);
            } else if (self.wave.get(mx, my) == .socket and edit) {
                self.wave.set(mx, my, .lane);
            } else if (self.wave.get(mx, my) == .none and edit) {
                self.wave.set(mx, my, .socket);
            }

            if (self.wave.get(mx, my) == .socket and self.transistors >= cpu_transistor_cost) {
                self.wave.set(mx, my, .{ .cpu = .{} });
                self.transistors -= cpu_transistor_cost;
                rl.playSound(game.sound_map.get(.cpu_place).?);
            } else if (self.wave.get(mx, my) == .cpu) {
                var cpu = &self.wave.at(mx, my).?.cpu;
                if (cpu.upgradeBusWidth()) {
                    rl.playSound(game.sound_map.get(.cpu_upgrade).?);
                }
            }
        } else if (rl.isMouseButtonPressed(rl.MouseButton.right)) {
            if (self.wave.get(mx, my) == .cpu) {
                var cpu = &self.wave.at(mx, my).?.cpu;
                if (cpu.upgradeCacheSize()) {
                    rl.playSound(game.sound_map.get(.cpu_upgrade).?);
                }
            }

            if (edit) {
                self.wave.set(mx, my, .none);
            }
        }

        if (rl.isKeyPressed(rl.KeyboardKey.s) and debug) {
            const f = std.io.getStdErr().writer();
            std.zon.stringify.serializeArbitraryDepth(self.wave.map, .{
                .whitespace = false,
            }, f) catch unreachable;
            f.writeByte('\n') catch unreachable;
            unreachable;
        }
    }

    fn updateCpuAndBugs(self: *ScreenBattle, game: *Game, dt: f32) void {
        const map = self.wave.map;

        for (0..map.len) |y| {
            for (0..map[0].len) |x| {
                const cell = self.wave.at(x, y).?;
                switch (cell.*) {
                    .cpu => {
                        var cpu = &cell.cpu;

                        const cpu_center = rl.Vector2.init(
                            @as(f32, @floatFromInt(x)) * cell_size + cell_size / 2,
                            @as(f32, @floatFromInt(y)) * cell_size + cell_size / 2,
                        );

                        var count: u32 = 0;
                        const radius = cpu.cache_size * cell_size;
                        for (self.wave.bugs.items) |*bug| {
                            if (bug.dead) {
                                continue;
                            }
                            if (count >= cpu.cores()) {
                                break;
                            }

                            const distance = cpu_center.subtract(bug.position).length();
                            if (distance > radius) {
                                continue;
                            }

                            if (bug.damage(cpu.damage() * dt)) {
                                cpu.debugs += 1;
                                rl.playSound(game.sound_map.get(.bug_death).?);
                                self.transistors += bug.transistors();
                            }

                            count += 1;
                        }
                    },
                    else => continue,
                }
            }
        }
    }

    fn updateCamera(self: *ScreenBattle) void {
        screen_width = rl.getScreenWidth();
        screen_height = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screen_width)) / 2,
            .y = @as(f32, @floatFromInt(screen_height)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screen_width)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screen_height)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }

    fn render(self: *ScreenBattle, game: *Game) void {
        const a = game.frame_arena.allocator();
        const map = self.wave.map;

        self.popup = false; // reset popup

        {
            rl.beginMode2D(self.camera);
            defer rl.endMode2D();

            // TODO: make bugs render between (on top of) lanes and (under) AI
            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    self.drawCell(game, x, y);
                }
            }

            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    const cell = self.wave.get(x, y);
                    switch (cell) {
                        .cpu => |cpu| {
                            const cpu_center = rl.Vector2.init(
                                @as(f32, @floatFromInt(x)) * cell_size + cell_size / 2,
                                @as(f32, @floatFromInt(y)) * cell_size + cell_size / 2,
                            );

                            var count: u32 = 0;
                            const radius = cpu.cache_size * cell_size;
                            for (self.wave.bugs.items) |bug| {
                                if (bug.dead) {
                                    continue;
                                }
                                if (count >= cpu.cores()) {
                                    break;
                                }

                                const distance = cpu_center.subtract(bug.position).length();
                                if (distance > radius) {
                                    continue;
                                }

                                rl.drawLineEx(cpu_center, bug.position, cpu.bus_width, rl.Color.red);
                                count += 1;
                            }

                            if (debug) {
                                rl.drawCircleLinesV(cpu_center, cpu.cache_size * cell_size, rl.Color.green);
                            }
                        },
                        else => continue,
                    }
                }
            }

            for (self.wave.bugs.items) |bug| {
                if (bug.dead) {
                    continue;
                }
                const texture = switch (bug.kind) {
                    .nullptr_deref => game.texture_map.get(.bug_null).?,
                    .stack_overflow => game.texture_map.get(.bug_stackoverflow).?,
                    .infinite_loop => game.texture_map.get(.bug_while).?,
                };

                // const angle_deg = bug.angle;
                const angle_deg = 0;
                const angle_rad = angle_deg * (std.math.pi / 180.0);
                const origin_x = cos(angle_rad) * (cell_size / 2) - sin(angle_rad) * (cell_size / 2);
                const origin_y = sin(angle_rad) * (cell_size / 2) + cos(angle_rad) * (cell_size / 2);

                const draw_x = bug.position.x - origin_x;
                const draw_y = bug.position.y - origin_y;

                rl.drawTexturePro(
                    texture,
                    .{ .x = bug.animation_state * cell_size, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = draw_x, .y = draw_y, .width = cell_size, .height = cell_size },
                    rl.Vector2.zero(),
                    angle_deg,
                    rl.Color.white,
                );
            }

            const font_size = 24;

            const transistor_texture = game.texture_map.get(.transistor).?;
            rl.drawTexture(transistor_texture, 0, cell_size / 4, rl.Color.white);

            const transistors_count = std.fmt.allocPrintZ(a, "{d}", .{self.transistors}) catch unreachable;
            rl.drawTextEx(
                game.font_title,
                transistors_count,
                .{ .x = cell_size, .y = (cell_size + font_size) / 4 },
                font_size,
                1,
                .white,
            );

            const offset = world_height - cell_size;
            const cpu_texture = game.texture_map.get(.cpu_pins).?;
            rl.drawTexture(cpu_texture, 0, offset, rl.Color.white);
            rl.drawTextureEx(
                transistor_texture,
                .{ .x = cell_size + cell_size / 3, .y = offset + 6 },
                0,
                0.5,
                rl.Color.white,
            );

            const cpu_cost = std.fmt.allocPrintZ(a, "= {d}", .{cpu_transistor_cost}) catch unreachable;
            rl.drawTextEx(
                game.font_title,
                cpu_cost,
                .{ .x = cell_size, .y = offset + (font_size) / 8 },
                font_size,
                1,
                .white,
            );

            if (self.popup) {
                const msp = getMousePos(&self.camera);
                const upgrade_texture = game.texture_map.get(.upgrade_popup).?;
                const scale = 2;
                const pos = msp.subtract(.{ .x = cell_size / 2 * scale, .y = cell_size * scale });
                rl.drawTexturePro(
                    upgrade_texture,
                    .{ .x = 0, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = pos.x, .y = pos.y, .width = cell_size * scale, .height = cell_size * scale },
                    rl.Vector2.zero(),
                    0,
                    rl.Color.white,
                );
            }
        }

        if (debug) {
            rl.drawRectangle(
                10,
                10,
                @divTrunc(screen_width, 5),
                @divTrunc(screen_height, 5),
                rl.fade(rl.Color.white, 0.6),
            );
            rl.drawRectangleLines(
                10,
                10,
                @divTrunc(screen_width, 5),
                @divTrunc(screen_height, 5),
                rl.Color.black,
            );

            const debug_font_size = @divTrunc(screen_width, 80);

            const debug_info = std.fmt.allocPrintZ(a,
                \\FPS: {}
                \\Screen: {}x{}
                \\World: {}x{} ({})
                \\Bugs: {}
                \\Ram: {d}/{d}
                \\Transistors: {d}
            , .{
                rl.getFPS(),
                screen_width,
                screen_height,
                world_width,
                world_height,
                cell_size,
                self.wave.bugs.items.len,
                self.ram,
                max_ram,
                self.transistors,
            }) catch return;

            rl.drawText(debug_info, 20, 20, debug_font_size, .black);
        }
    }

    fn drawCell(self: *ScreenBattle, game: *Game, x: usize, y: usize) void {
        switch (self.wave.map[y][x]) {
            .none => return,
            .socket => {
                const texture = game.texture_map.get(.socket).?;
                rl.drawTexture(texture, @intCast(x * cell_size), @intCast(y * cell_size), rl.Color.white);
            },
            .lane => {
                const texture = game.texture_map.get(.lane).?;

                const lane_left = self.wave.get(x - 1, y).isLaneConnected();
                const lane_right = self.wave.get(x + 1, y).isLaneConnected();
                const lane_top = self.wave.get(x, y - 1).isLaneConnected();
                const lane_bottom = self.wave.get(x, y + 1).isLaneConnected();

                var offset: f32 = undefined;
                // Choose the correct sprite
                if (lane_top and lane_left) {
                    offset = 3;
                } else if (lane_top and lane_right) {
                    offset = 2;
                } else if (lane_bottom and lane_left) {
                    offset = 5;
                } else if (lane_bottom and lane_right) {
                    offset = 4;
                } else if (lane_left or lane_right) {
                    offset = 0;
                } else if (lane_top or lane_bottom) {
                    offset = 1;
                }

                rl.drawTextureRec(
                    texture,
                    .{ .x = offset * cell_size, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = @floatFromInt(x * cell_size), .y = @floatFromInt(y * cell_size) },
                    rl.Color.white,
                );
            },
            .cpu => |cpu| {
                const texture = game.texture_map.get(.cpu).?;

                const msp = getMousePos(&self.camera);
                const mx: usize = @intFromFloat(msp.x / cell_size);
                const my: usize = @intFromFloat(msp.y / cell_size);
                const hovered = mx == x and my == y;
                if (hovered) {
                    rl.drawRectangle(
                        @intCast(x * cell_size),
                        @intCast(y * cell_size),
                        cell_size,
                        cell_size,
                        highlight_color,
                    );
                }

                const offset: f32 = @floatFromInt(cpu.level() - 1);
                rl.drawTextureRec(
                    texture,
                    .{ .x = offset * cell_size, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = @floatFromInt(x * cell_size), .y = @floatFromInt(y * cell_size) },
                    rl.Color.white,
                );

                if (cpu.hasUpgrades() and hovered) {
                    self.popup = true;
                }
            },
            .ai => {
                const texture = game.texture_map.get(.ai).?;
                rl.drawTexture(texture, @intCast(x * cell_size), @intCast(y * cell_size), rl.Color.white);
            },
            .ram => {
                const texture = game.texture_map.get(.ram).?;

                const offset: f32 = if (self.ram == 0) 4 else if (self.ram / max_ram > 0.75) 0 else if (self.ram / max_ram > 0.5) 1 else if (self.ram / max_ram > 0.25) 2 else 3;

                rl.drawTextureRec(
                    texture,
                    .{ .x = offset * cell_size, .y = 0, .width = cell_size, .height = cell_size * 3 },
                    .{ .x = @floatFromInt(x * cell_size), .y = @floatFromInt(y * cell_size - cell_size) },
                    rl.Color.white,
                );
            },
        }
    }
};
