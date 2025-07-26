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
const highlight_color = rl.Color.init(0x57, 0x72, 0x77, 0xFF);

const debug = true;
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
fn getMousePos(camera: *rl.Camera2D) rl.Vector2 {
    const msp = rl.getMousePosition().scale(1 / camera.zoom);

    return .{
        .x = @max(msp.x, 0),
        .y = @max(msp.y, 0),
    };
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

    pub fn update(self: *Bug, delta_time: f32, wave: *Wave, ram: *f32, game: *Game) void {
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
                target = self.target.add(rl.Vector2.init(0, -cell_size));
                std.debug.print("lane top\n", .{});
            }
            if (lane_bottom and prev_grid_y != target_grid_y + 1) {
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

    pub fn maxHealth(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 3,
            .stack_overflow => return 100,
            .infinite_loop => return 1,
        };
    }

    fn speed(kind: BugKind) f32 {
        return switch (kind) {
            .nullptr_deref => return 0.3,
            .stack_overflow => return 0.1,
            .infinite_loop => return 1,
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
            .infinite_loop => return 7,
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
            0...2 => 1,
            3...4 => 2,
            5...6 => 3,
            7...8 => 4,
            else => 5,
            // 0...9 => 1,
            // 10...24 => 2,
            // 25...49 => 3,
            // 50...100 => 4,
            // else => 5,
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

            spawn_rules.append(.{
                .from_time_s = 0,
                .to_time_s = 30,
                .bugs = .{
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
                    .{ .spawn_interval = 0.5 },
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

    fn update(self: *Wave, delta_time: f32, ram: *f32, game: *Game) void {
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
            bug.update(delta_time, self, ram, game);
        }
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
};

const SoundKind = enum {
    bug_death,
    bug_attack,
    ram_destroyed,
    cpu_place,
    cpu_upgrade,
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
        sound_map.put(.bug_death, bug_death) catch unreachable;
        sound_map.put(.bug_attack, bug_attack) catch unreachable;
        sound_map.put(.ram_destroyed, ram_destroyed) catch unreachable;
        sound_map.put(.cpu_place, cpu_place) catch unreachable;
        sound_map.put(.cpu_upgrade, cpu_upgrade) catch unreachable;

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
                .main = .init(),
                // .gameover = .init(),
                // .battle = .init(),
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
            .main => |_| {
                self.screen_state.main.update(self, dt);
            },
            .battle => |_| {
                self.screen_state.battle.update(self, dt);
            },
            .gameover => |_| {
                self.screen_state.gameover.update(self, dt);
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
            .gameover => |_| {
                self.screen_state.gameover.render(self);
            },
        }
    }
};

const ScreenMainMenu = struct {
    camera: rl.Camera2D,
    pressed_start: bool = false,

    const start_button_size: f32 = @floatFromInt(cell_size);
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
            const battle = ScreenBattle.init();
            game.screen_state = .{ .battle = battle };
        }
    }

    fn render(self: *ScreenMainMenu, game: *Game) void {
        rl.beginMode2D(self.camera);
        defer rl.endMode2D();

        const title_pos: rl.Vector2 = .{
            .x = (world_width - ScreenMainMenu.title_size) / 2,
            .y = (world_height - ScreenMainMenu.title_size) / 2 - 50,
        };

        rl.drawTextureRec(
            game.texture_map.get(.cpus_vs_bugs).?,
            .{
                .x = 0,
                .y = 0,
                .width = ScreenMainMenu.title_size,
                .height = cell_size,
            },
            title_pos,
            rl.Color.white,
        );

        rl.drawTextEx(game.font_title, "CPU", title_pos.add(.{ .x = 33, .y = 5 }), 22, 3, rl.Color.white);

        rl.drawTextEx(game.font_title, "AI", title_pos.add(.{ .x = 100, .y = 5 }), 22, 3, rl.Color.white);

        const button_pos: rl.Vector2 = .{
            .x = (world_width - ScreenMainMenu.start_button_size) / 2,
            .y = (world_height - ScreenMainMenu.start_button_size) / 2 + 40,
        };

        const rect = rl.Rectangle.init(
            button_pos.x,
            button_pos.y,
            ScreenMainMenu.start_button_size,
            ScreenMainMenu.start_button_size,
        );

        const msp = getMousePos(&self.camera);

        const ms_rect = rl.Rectangle.init(msp.x, msp.y, 1, 1);

        self.pressed_start = rect.checkCollision(ms_rect) and rl.isMouseButtonPressed(.left);

        rl.drawTextureRec(
            game.texture_map.get(.power_button).?,
            .{
                .x = 0,
                .y = 0,
                .width = ScreenMainMenu.start_button_size,
                .height = ScreenMainMenu.start_button_size,
            },
            button_pos,
            rl.Color.white,
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

    const button_size: f32 = @floatFromInt(cell_size);

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
        _ = dt;
        if (self.pressed_retry) {
            game.screen_state = .{ .battle = .init() };
        }
        if (self.pressed_menu) {
            game.screen_state = .{ .main = .init() };
        }

        self.updateCamera();
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

        // get text dimensions for "Game Over" at size 22
        // imagined func: const text_dimensions = rl.getTextSizeEx(game.font_title, "Game Over", 22);
        const td = rl.measureTextEx(game.font_title, "Game Over", 22, 1.0);
        std.log.info("Text dimensions: x={}, y={}, world_width={}, world_height={}", .{ td.x, td.y, world_width, world_height });
        rl.drawTextEx(game.font_title, "Game Over", .{ .x = (world_width - td.x) / 2, .y = (world_height - td.y) / 2 }, 22, 1.0, rl.Color.red);

        //const msp = getMousePos(&self.camera);
        self.pressed_menu = rl.isMouseButtonPressed(.left);
    }
};

// TODO: ScreenVictory

const ScreenBattle = struct {
    camera: rl.Camera2D,
    wave: Wave,
    ram: f32, // health of the player
    transistors: f32 = 0,

    popup: bool = false,

    const max_ram = 100;
    const cpu_transistor_cost = 100;

    fn init() ScreenBattle {
        return .{
            .wave = .init(1),
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
            .transistors = 100,
        };
    }

    fn deinit(self: *ScreenBattle) void {
        self.wave.deinit();
    }

    fn update(self: *ScreenBattle, game: *Game, dt: f32) void {
        self.handlePlayerInput(game, dt);

        self.wave.update(dt, &self.ram, game);
        self.updateCpuAndBugs(game, dt);

        self.updateCamera();

        if (self.ram <= 0) {
            self.deinit();
            game.screen_state = .{ .gameover = .init() };
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
                // self.transistors -= cpu_transistor_cost; // TODO: uncomment when playtesting
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
        const half_cell = cell_size / 2;

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

                rl.drawTextureRec(
                    texture,
                    .{ .x = bug.animation_state * cell_size, .y = 0, .width = cell_size, .height = cell_size },
                    .{ .x = bug.position.x - half_cell, .y = bug.position.y - half_cell },
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
