const std = @import("std");
const rl = @import("raylib");
const rlg = @import("raygui");
const assert = std.debug.assert;

const cell_size = 32;
const cells_width = 16.0;
const cells_height = 9.0;
const world_width = cells_width * cell_size;
const world_height = cells_height * cell_size;
const bg_color = rl.Color.init(0x20, 0x2e, 0x37, 0xFF);

const debug = false;

var screenWidth: i32 = 1280;
var screenHeight: i32 = 720;

const image_assets = [_][]const u8{
    "",
};

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.initWindow(screenWidth, screenHeight, "Hackathon");
    defer rl.closeWindow(); // Close window and OpenGL context
    rl.setWindowState(.{ .window_resizable = true });

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.caps_lock);
    //--------------------------------------------------------------------------------------

    var game = Game.init();
    defer game.deinit();

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

    pub fn update(self: *Bug, delta_time: f32, wave: *Wave, ram: *f32) void {
        self.animation_time += delta_time;
        if (self.animation_time > animationSwitchThreshold(self.kind)) {
            self.animation_time = 0;
            self.animation_state = @mod((self.animation_state + 1), animationCount(self.kind));
        }

        var velocity: rl.Vector2 = self.target.subtract(self.position);
        velocity = velocity.normalize().scale(speed(self.kind));
        self.position = self.position.add(velocity);

        // 1 is 1/32th of a cell
        if (self.position.distanceSqr(self.target) < 1) {
            // Find new target
            const prev_grid_x: usize = @intFromFloat(self.previous.x / cell_size);
            const prev_grid_y: usize = @intFromFloat(self.previous.y / cell_size);
            const target_grid_x: usize = @intFromFloat(self.target.x / cell_size);
            const target_grid_y: usize = @intFromFloat(self.target.y / cell_size);

            const lane_left = wave.get(target_grid_x - 1, target_grid_y).isLaneConnected();
            const lane_right = wave.get(target_grid_x + 1, target_grid_y).isLaneConnected();
            // TODO: are these correct or flipped
            const lane_top = wave.get(target_grid_x, target_grid_y - 1).isLaneConnected();
            const lane_bottom = wave.get(target_grid_x, target_grid_y + 1).isLaneConnected();

            std.debug.print("prev_grid_x: {}, prev_grid_y: {}\n", .{ prev_grid_x, prev_grid_y });
            std.debug.print("target_grid_x: {}, target_grid_y: {}\n", .{ target_grid_x, target_grid_y });

            std.debug.print("lane left: {}, lane right: {}, lane top: {}, lane bottom: {}\n", .{
                lane_left,
                lane_right,
                lane_top,
                lane_bottom,
            });

            var target: rl.Vector2 = rl.Vector2.init(0, 0);
            if (lane_left and prev_grid_x != target_grid_x - 1) {
                target = self.target.add(rl.Vector2.init(-cell_size, 0));
                std.debug.print("lane left\n", .{});
            }
            if (lane_right and prev_grid_x != target_grid_x + 1) {
                target = self.target.add(rl.Vector2.init(cell_size, 0));
                std.debug.print("lane right\n", .{});
            }
            if (lane_top and prev_grid_y != target_grid_y - 1) {
                // TODO: are these correct or flipped
                target = self.target.add(rl.Vector2.init(0, -cell_size));
                std.debug.print("lane top\n", .{});
            }
            if (lane_bottom and prev_grid_y != target_grid_y + 1) {
                // TODO: are these correct or flipped
                target = self.target.add(rl.Vector2.init(0, cell_size));
                std.debug.print("lane bottom\n", .{});
            }
            if (target.x == 0 and target.y == 0) {
                unreachable;
            }

            self.previous = self.target;
            self.target = target;

            if (wave.get(target_grid_x + 1, target_grid_y) == .ram) {
                ram.* = @max(ram.* - self.damage(), 0);
                self.dead = true;
            }
        }
    }

    pub fn maxHealth(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 30,
            .stack_overflow => return 100,
            .infinite_loop => return 10,
        };
    }

    fn speed(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 0.3,
            .stack_overflow => return 0.1,
            .infinite_loop => return 1,
        };
    }

    fn damage(self: Bug) f32 {
        return switch (self.kind) {
            .nullptr_deref => return 10,
            .stack_overflow => return 20,
            .infinite_loop => return 33,
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
        return switch (kind) {
            .nullptr_deref => return 0.3,
            .stack_overflow => return 0.3,
            .infinite_loop => return 0.05,
        };
    }
};

const Condition = union(enum) {
    always,
    memory_leak: f32, // Health percentage, ram<0.25 or ram<0.5 (randomized)
    bug: BugKind, // Against this specific enemy type
    idle: f32, // Idle time in seconds, 1s-2s (randomized)
};

const Instruction = struct {
    condition: Condition,
    opcode: Opcode,

    const Opcode = union(enum) {
        sleep: f32, // Slows enemies (multiplier of enemy speed, 0.5-0.9 randomized)
        prefetch: f32, // Deals more damage (multiplier of cache size, 1.5-2 randomized)
        overclock: f32, // Faster firerate (multiplier of clock speed, 1.1-1.5 randomized)
    };
};

const Cpu = struct {
    clock_speed: f32 = 1, // Fire rate, every how many seconds to fire
    cache_size: f32 = 1, // Cache size, damage dealt
    debugs: u32 = 0, // How many bugs were killed
    instructions: []Instruction, // modifiers

    fn cores(self: Cpu) u32 {
        return switch (self.debugs) {
            0...10 => 1,
            10...25 => 2,
            25...50 => 3,
            50...100 => 4,
            else => 5,
        };
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

            spawn_rules.append(.{
                .from_time_s = 0,
                .to_time_s = 10,
                .bugs = .{
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 0 },
                    .{ .spawn_interval = 3 },
                },
            }) catch unreachable;
            // spawn_rules.append(.{
            //     .from_time_s = 0,
            //     .to_time_s = 10,
            //     .bugs = .{
            //         .{ .spawn_interval = 1 },
            //         .{ .spawn_interval = 0 },
            //         .{ .spawn_interval = 0 },
            //     },
            // }) catch unreachable;
            //
            // spawn_rules.append(.{
            //     .from_time_s = 10,
            //     .to_time_s = 20,
            //     .bugs = .{
            //         .{ .spawn_interval = 2 },
            //         .{ .spawn_interval = 0.5 },
            //         .{ .spawn_interval = 0 },
            //     },
            // }) catch unreachable;
            //
            // spawn_rules.append(.{
            //     .from_time_s = 20,
            //     .to_time_s = 30,
            //     .bugs = .{
            //         .{ .spawn_interval = 5 },
            //         .{ .spawn_interval = 1 },
            //         .{ .spawn_interval = 0.5 },
            //     },
            // }) catch unreachable;
        } else if (wave_number == 2) {
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
            map = .{
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none, .none },
                .{ .none, .socket, .socket, .socket, .socket, .socket, .none, .none, .none, .none, .none, .none, .socket, .socket, .socket, .none },
                .{ .ai, .lane, .lane, .lane, .lane, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .lane, .lane, .ram },
                .{ .none, .socket, .socket, .socket, .lane, .socket, .socket, .lane, .lane, .lane, .lane, .lane, .socket, .lane, .socket, .none },
                .{ .none, .none, .none, .socket, .lane, .lane, .lane, .lane, .socket, .socket, .socket, .lane, .lane, .lane, .socket, .none },
                .{ .none, .none, .none, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .socket, .none },
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

    fn update(self: *Wave, delta_time: f32, ram: *f32) void {
        // TODO: quite a bit of logic here
        self.time_since_start += delta_time;

        const half_cell = cell_size / 2;
        const ai_position = rl.Vector2.init(half_cell, 4 * cell_size + half_cell);

        // TODO: post hackathon, optimize this
        for (self.spawn_rules.items) |*rules| {
            if (rules.from_time_s > self.time_since_start or rules.to_time_s < self.time_since_start) {
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
            bug.update(delta_time, self, ram);
        }
    }

    fn deinit(self: *Wave) void {
        self.arena.deinit();
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
    socket,
    lane,
    ai,
    ram,
    bug_null,
    bug_while,
    bug_stackoverflow,
};

const Game = struct {
    global_arena: std.heap.ArenaAllocator,
    frame_arena: std.heap.ArenaAllocator,

    texture_map: std.AutoHashMap(TextureKind, rl.Texture2D),

    font_title: rl.Font,
    font_normal: rl.Font,

    screen_state: union(enum) {
        main: ScreenMainMenu,
        battle: ScreenBattle,
    },

    fn init() Game {
        var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const ga = global_arena.allocator();
        var texture_map = std.AutoHashMap(TextureKind, rl.Texture2D).init(ga);

        // TODO: make this texture loading more dynamic - DO THIS AFTER JAM
        const lane = rl.loadTexture("assets/img/lane.png") catch unreachable;
        const socket = rl.loadTexture("assets/img/socket.png") catch unreachable;
        const ai = rl.loadTexture("assets/img/ai.png") catch unreachable;
        const bug_so = rl.loadTexture("assets/img/stackoverflow.png") catch unreachable;
        const bug_null = rl.loadTexture("assets/img/nullptr-deref.png") catch unreachable;
        const bug_while = rl.loadTexture("assets/img/while1.png") catch unreachable;
        const ram = rl.loadTexture("assets/img/ram.png") catch unreachable;
        texture_map.put(.socket, socket) catch unreachable;
        texture_map.put(.lane, lane) catch unreachable;
        texture_map.put(.ai, ai) catch unreachable;
        texture_map.put(.bug_null, bug_null) catch unreachable;
        texture_map.put(.bug_stackoverflow, bug_so) catch unreachable;
        texture_map.put(.bug_while, bug_while) catch unreachable;
        texture_map.put(.ram, ram) catch unreachable;

        const font_title = rl.loadFontEx("assets/font/DepartureMonoNerdFontMono-Regular.otf", 80, null) catch unreachable;
        const font_normal = rl.loadFontEx("assets/font/GohuFont14NerdFontMono-Regular.ttf", 80, null) catch unreachable;

        return .{
            .global_arena = global_arena,
            .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .texture_map = texture_map,
            .font_title = font_title,
            .font_normal = font_normal,
            .screen_state = .{
                // .main = .init(),
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

        std.debug.print("Delta time: {d}\n", .{dt});

        // TODO: find a better method of mutating the original
        switch (self.screen_state) {
            .main => |_| {
                self.screen_state.main.update(self, dt);
            },
            .battle => |_| {
                self.screen_state.battle.update(self, dt);
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
            .main => |_| {
                self.screen_state.main.render(self);
            },
            .battle => |_| {
                self.screen_state.battle.render(self);
            },
        }
    }
};

const ScreenMainMenu = struct {
    camera: rl.Camera2D,
    pressed_start: bool = false,
    pressed_options: bool = false,

    fn init() ScreenMainMenu {
        return .{
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screenWidth)) / 2,
                    .y = @as(f32, @floatFromInt(screenHeight)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screenHeight)) / world_height,
            },
        };
    }

    fn update(self: *ScreenMainMenu, game: *Game, dt: f32) void {
        _ = dt;

        self.updateCamera();

        if (self.pressed_start) {
            const battle = ScreenBattle.init();
            game.screen_state = .{ .battle = battle };
        }
    }

    fn render(self: *ScreenMainMenu, game: *Game) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();

        const msp = rl.getMousePosition().scale(1 / self.camera.zoom);

        rl.drawRectangleRec(rl.Rectangle.init(msp.x, msp.y, 100, 100), rl.Color.white);

        // what are we actually calling this game?
        rl.drawTextEx(game.font_title, "Bug Defenders", rl.Vector2.init(495, 160), 40, 4, rl.Color.white);

        self.pressed_start = rlg.button(.{ .x = 540, .y = 410, .width = 200, .height = 75 }, "Play");

        // TODO: after the hackathon, add an options menu
        //self.pressed_options = rlg.button(.{ .x = 285, .y = 280, .width = 300, .height = 100 }, "Options");
    }

    fn updateCamera(self: *ScreenMainMenu) void {
        screenWidth = rl.getScreenWidth();
        screenHeight = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screenWidth)) / 2,
            .y = @as(f32, @floatFromInt(screenHeight)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screenWidth)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screenHeight)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }
};

const ScreenBattle = struct {
    camera: rl.Camera2D,
    wave: Wave,
    ram: f32, // health of the player
    const max_ram = 100;

    fn init() ScreenBattle {
        return .{
            .wave = .init(1),
            .camera = .{
                .target = .{ .x = 128, .y = 128 },
                .offset = .{
                    .x = @as(f32, @floatFromInt(screenWidth)) / 2,
                    .y = @as(f32, @floatFromInt(screenHeight)) / 2,
                },
                .rotation = 0,
                .zoom = @as(f32, @floatFromInt(screenHeight)) / world_height,
            },
            .ram = max_ram,
        };
    }

    fn update(self: *ScreenBattle, game: *Game, dt: f32) void {
        _ = game;

        self.handlePlayerInput(dt);

        self.wave.update(dt, &self.ram);

        self.updateCamera();
    }

    fn handlePlayerInput(self: *ScreenBattle, dt: f32) void {
        _ = dt;

        const msp = rl.getMousePosition().scale(1 / self.camera.zoom);
        const mx: usize = @intFromFloat(msp.x / cell_size);
        const my: usize = @intFromFloat(msp.y / cell_size);

        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            if (self.wave.get(mx, my) == .lane and debug) {
                self.wave.set(mx, my, .socket);
            } else if (self.wave.get(mx, my) == .socket and debug) {
                self.wave.set(mx, my, .lane);
            } else if (self.wave.get(mx, my) == .none and debug) {
                self.wave.set(mx, my, .socket);
            }

            // if (self.wave.get(mx, my) == .socket) {
            //     self.wave.set(mx, my, .cpu);
            // }

        } else if (rl.isMouseButtonPressed(rl.MouseButton.right) and debug) {
            self.wave.set(mx, my, .none);
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

    fn updateCamera(self: *ScreenBattle) void {
        screenWidth = rl.getScreenWidth();
        screenHeight = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screenWidth)) / 2,
            .y = @as(f32, @floatFromInt(screenHeight)) / 2,
        };

        self.camera.target = .{
            .x = world_width / 2.0,
            .y = world_height / 2.0,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screenWidth)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screenHeight)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }

    fn render(self: *ScreenBattle, game: *Game) void {
        const a = game.frame_arena.allocator();
        const map = self.wave.map;

        {
            rl.beginMode2D(self.camera);
            defer rl.endMode2D();

            // TODO: make bugs render between (on top of) lanes and (under) AI
            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    self.drawCell(game, x, y);
                }
            }

            const half_cell = cell_size / 2;

            for (self.wave.bugs.items) |bug| {
                if (bug.dead) {
                    continue;
                }
                const texture = switch (bug.kind) {
                    .nullptr_deref => game.texture_map.get(.bug_null).?,
                    .stack_overflow => game.texture_map.get(.bug_stackoverflow).?,
                    .infinite_loop => game.texture_map.get(.bug_while).?,
                };

                rl.drawTextureRec(
                    texture,
                    .{ .x = bug.animation_state * cell_size, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = bug.position.x - half_cell, .y = bug.position.y - half_cell },
                    rl.Color.white,
                );
            }
        }

        rl.drawRectangle(
            10,
            10,
            @divTrunc(screenWidth, 5),
            @divTrunc(screenHeight, 5),
            rl.fade(rl.Color.white, 0.6),
        );
        rl.drawRectangleLines(
            10,
            10,
            @divTrunc(screenWidth, 5),
            @divTrunc(screenHeight, 5),
            rl.Color.black,
        );

        const font_size = @divTrunc(screenWidth, 80);

        const debug_info = std.fmt.allocPrintZ(a,
            \\FPS: {}
            \\Screen: {}x{}
            \\World: {}x{} ({})
            \\Bugs: {}
            \\Ram: {d}/{d}
        , .{
            rl.getFPS(),
            screenWidth,
            screenHeight,
            world_width,
            world_height,
            cell_size,
            self.wave.bugs.items.len,
            self.ram,
            max_ram,
        }) catch return;

        rl.drawText(debug_info, 20, 20, font_size, .black);
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
            .cpu => {},
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
