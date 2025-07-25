const std = @import("std");
const rl = @import("raylib");
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

const Cpu = struct {};

const Cell = union(enum) {
    none,
    socket,
    cpu: Cpu,
    ai,
    lane,
    color: rl.Color,

    fn isLaneConnected(self: Cell) bool {
        return switch (self) {
            .lane => true,
            .ai => true,
            else => false,
        };
    }
};

const Wave = struct {
    arena: std.heap.ArenaAllocator,
    map: [cells_height][cells_width]Cell = [_][cells_width]Cell{[_]Cell{.none} ** cells_width} ** cells_height,

    fn init() Wave {
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

        for (1..cells_width - 1) |x| {
            wave.map[cells_height - 2][x] = .lane;
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

const Game = struct {
    global_arena: std.heap.ArenaAllocator,
    frame_arena: std.heap.ArenaAllocator,

    texture_map: std.AutoHashMap(Cell, rl.Texture2D),

    camera: rl.Camera2D,
    wave: Wave,

    fn init() Game {
        var global_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const ga = global_arena.allocator();
        var texture_map = std.AutoHashMap(Cell, rl.Texture2D).init(ga);

        const lane = rl.loadTexture("assets/socket.png") catch unreachable;
        const socket = rl.loadTexture("assets/lane.png") catch unreachable;
        texture_map.put(.socket, lane) catch unreachable;
        texture_map.put(.lane, socket) catch unreachable;

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

        self.updateCamera();
    }

    fn render(self: *Game) void {
        const a = self.frame_arena.allocator();
        const map = self.wave.map;
        const camera = self.camera;

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    drawCell(self, x, y);
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

    fn drawCell(self: *Game, x: usize, y: usize) void {
        switch (self.wave.map[y][x]) {
            .none => return,
            .socket => {
                const texture = self.texture_map.get(.socket).?;
                rl.drawTexture(texture, @intCast(x * cell_size), @intCast(y * cell_size), rl.Color.white);
            },
            .lane => {
                const texture = self.texture_map.get(.lane).?;

                const lane_left = self.wave.get(x - 1, y).isLaneConnected();
                const lane_right = self.wave.get(x + 1, y).isLaneConnected();
                const lane_top = self.wave.get(x, y - 1).isLaneConnected();
                const lane_bottom = self.wave.get(x, y + 1).isLaneConnected();

                var offset: f32 = undefined;
                if (lane_top and lane_left) {
                    offset = 3;
                }
                // TODO(kyren): do the rest

                rl.drawTextureRec(
                    texture,
                    .{ .x = 0, .y = offset * cell_size, .width = cell_size, .height = cell_size },
                    .{ .x = @floatFromInt(x * cell_size), .y = @floatFromInt(y * cell_size) },
                    rl.Color.white,
                );
            },
            .cpu => {},
            .ai => {},
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
