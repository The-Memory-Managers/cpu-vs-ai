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

var screenWidth: i32 = 1280;
var screenHeight: i32 = 720;

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.initWindow(screenWidth, screenHeight, "Hackathon");
    defer rl.closeWindow(); // Close window and OpenGL context
    // rl.setWindowState(.{ .window_resizable = true });

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

const BugKind = enum {
    nullptr_deref,
    stack_overflow,
    infinite_loop,
};

const Bug = struct {
    kind: BugKind,
    health: f32,
    position: rl.Vector2,
    previous: rl.Vector2, // Center of prev
    target: rl.Vector2, // Center of next cell
    // TODO: bugs need to know their "previous" square, so they know their next

    pub fn init(kind: BugKind, position: rl.Vector2) Bug {
        return Bug{
            .kind = kind,
            .health = maxHealth(kind),
            .position = position,
            .previous = position,
            .target = position,
        };
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
            .nullptr_deref => return 30,
            .stack_overflow => return 10,
            .infinite_loop => return 100,
        };
    }

    fn damage(self: Bug) f32 {
        return switch (self.kind) {
            .nullptr_deref => return 1,
            .stack_overflow => return 2,
            .infinite_loop => return 0.5,
        } * self.health;
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
    lane,
    color: rl.Color,

    fn isLaneConnected(self: Cell) bool {
        return switch (self) {
            .lane => false,
            .ai => true,
            else => false,
        };
    }
};

const Wave = struct {
    arena: std.heap.ArenaAllocator,
    map: [cells_height][cells_width]Cell = [_][cells_width]Cell{[_]Cell{.none} ** cells_width} ** cells_height,

    fn init() Wave {
        const height_middle = 4;

        var wave = Wave{
            .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };

        for (1..cells_height - 1) |y| {
            for (1..cells_width - 1) |x| {
                const isEven = (y + x) % 2 == 0;
                if (isEven) {
                    wave.map[y][x] = .{ .color = rl.Color.blue };
                } else {
                    wave.map[y][x] = .socket;
                }
            }
        }

        wave.map[height_middle][0] = .ai;
        for (1..cells_width - 1) |x| {
            wave.map[height_middle][x] = .lane;
        }

        return wave;
    }

    fn get(self: *Wave, x: usize, y: usize) Cell {
        if (x >= cells_width or y >= cells_height) {
            return .none;
        }
        return self.map[y][x];
    }
};

const TextureKind = enum {
    socket,
    lane,
    ai,
};

const Game = struct {
    global_arena: std.heap.ArenaAllocator,
    frame_arena: std.heap.ArenaAllocator,

    texture_map: std.AutoHashMap(TextureKind, rl.Texture2D),

    font_title: rl.Font,
    font_normal: rl.Font,

    camera: rl.Camera2D,
    wave: Wave,

    screen_state: union(enum) {
        main: ScreenMainMenu,
        battle: ScreenBattle,
    },

    fn init() Game {
        var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const ga = global_arena.allocator();
        var texture_map = std.AutoHashMap(TextureKind, rl.Texture2D).init(ga);

        const lane = rl.loadTexture("assets/img/lane.png") catch unreachable;
        const socket = rl.loadTexture("assets/img/socket.png") catch unreachable;
        const ai = rl.loadTexture("assets/img/ai.png") catch unreachable;
        texture_map.put(.socket, socket) catch unreachable;
        texture_map.put(.lane, lane) catch unreachable;
        texture_map.put(.ai, ai) catch unreachable;

        const font_title = rl.loadFont("assets/font/DepartureMonoNerdFontMono-Regular.otf") catch unreachable;
        const font_normal = rl.loadFont("assets/font/GohuFont14NerdFontMono-Regular.ttf") catch unreachable;

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
            .global_arena = global_arena,
            .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .wave = .init(),
            .texture_map = texture_map,
            .font_title = font_title,
            .font_normal = font_normal,
            .screen_state = .{
                //.battle = .{},
                .main = .{},
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
        std.debug.print("Delta time: {d}\n", .{rl.getFrameTime()});

        switch (self.screen_state) {
            .main => |m| {
                var mut_m = m;
                mut_m.update(self);
            },
            .battle => |b| {
                var mut_b = b;
                mut_b.update(self);
            },
        }

        self.updateCamera();
    }

    fn render(self: *Game) void {
        switch (self.screen_state) {
            .main => |m| {
                var mut_m = m;
                mut_m.render(self);
            },
            .battle => |b| {
                var mut_b = b;
                mut_b.render(self);
            },
        }
    }

    fn updateCamera(self: *Game) void {
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

const ScreenMainMenu = struct {
    fn update(self: *ScreenMainMenu, game: *Game) void {
        _ = self;
        _ = game;
    }

    fn render(self: *ScreenMainMenu, game: *Game) void {
        _ = self;

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        rl.drawTextEx(game.font_title, "Test", rl.Vector2.init(20, 20), 40, 4, rl.Color.white);

        if (rlg.button(.{ .x = 30, .y = 30, .width = 200, .height = 100 }, "Start")) {
            game.screen_state = .{ .battle = .{} };
        }
    }
};

const ScreenBattle = struct {
    fn update(self: *ScreenBattle, game: *Game) void {
        _ = self;
        _ = game;
    }

    fn render(self: *ScreenBattle, game: *Game) void {
        const a = game.frame_arena.allocator();
        const map = game.wave.map;
        const camera = game.camera;

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            // TODO: make bugs render between (on top of) lanes and (under) AI
            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    self.drawCell(game, x, y);
                }
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

        const debug_info = std.fmt.allocPrintZ(
            a,
            \\FPS: {}
            \\Screen: {}x{}
            \\World: {}x{} ({})
        ,
            .{ rl.getFPS(), screenWidth, screenHeight, world_width, world_height, cell_size },
        ) catch return;

        rl.drawText(debug_info, 20, 20, font_size, .black);
    }

    fn drawCell(self: *ScreenBattle, game: *Game, x: usize, y: usize) void {
        _ = self;

        switch (game.wave.map[y][x]) {
            .none => return,
            .socket => {
                const texture = game.texture_map.get(.socket).?;
                rl.drawTexture(texture, @intCast(x * cell_size), @intCast(y * cell_size), rl.Color.white);
            },
            .lane => {
                const texture = game.texture_map.get(.lane).?;

                const lane_left = game.wave.get(x - 1, y).isLaneConnected();
                const lane_right = game.wave.get(x + 1, y).isLaneConnected();
                const lane_top = game.wave.get(x, y - 1).isLaneConnected();
                const lane_bottom = game.wave.get(x, y + 1).isLaneConnected();

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
                    .{ .x = 0, .y = offset * cell_size, .width = cell_size, .height = cell_size },
                    .{ .x = @floatFromInt(x * cell_size), .y = @floatFromInt(y * cell_size) },
                    rl.Color.white,
                );
            },
            .cpu => {},
            .ai => {
                const texture = game.texture_map.get(.ai).?;
                rl.drawTexture(texture, @intCast(x * cell_size), @intCast(y * cell_size), rl.Color.white);
            },
            .color => |color| {
                rl.drawRectangle(
                    @intCast(x * cell_size),
                    @intCast(y * cell_size),
                    cell_size,
                    cell_size,
                    color,
                );
            },
        }
    }
};
