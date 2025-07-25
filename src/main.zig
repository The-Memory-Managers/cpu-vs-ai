const std = @import("std");
const rl = @import("raylib");
const assert = std.debug.assert;

const cell_size = 16;
const world_width = 16 * cell_size;
const world_height = 9 * cell_size;

var screen_width: i32 = 1280;
var screen_height: i32 = 720;

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------

    rl.initWindow(screen_width, screen_height, "Hackathon");
    defer rl.closeWindow(); // Close window and OpenGL context
    // rl.setWindowState(.{ .window_resizable = true });

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.caps_lock);
    //--------------------------------------------------------------------------------------

    var game = Game.init();

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

const Cell = struct {
    color: rl.Color = rl.Color.red,
};

const Wave = struct {
    arena: std.heap.ArenaAllocator,
    map: [world_height][world_width]Cell = [_][world_width]Cell{[_]Cell{Cell{}} ** world_width} ** world_height,
};

const Game = struct {
    camera: rl.Camera2D,
    frame_arena: std.heap.ArenaAllocator,
    wave: Wave,

    fn init() Game {
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
            .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .wave = .{
                .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            },
        };
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

        rl.clearBackground(rl.Color.sky_blue);

        {
            rl.beginMode2D(camera);
            defer rl.endMode2D();

            for (0..map.len) |y| {
                for (0..map[0].len) |x| {
                    const cell = map[y][x];
                    const isEven = (y + x) % 2 == 0;
                    if (isEven) {
                        rl.drawRectangle(
                            @intCast(x * cell_size),
                            @intCast(y * cell_size),
                            cell_size,
                            cell_size,
                            rl.Color.green,
                        );
                    } else {
                        rl.drawRectangle(
                            @intCast(x * cell_size),
                            @intCast(y * cell_size),
                            cell_size,
                            cell_size,
                            cell.color,
                        );
                    }
                }
            }
        }

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

        const font_size = @divTrunc(screen_width, 80);

        const debug_info = std.fmt.allocPrintZ(
            a,
            \\FPS: {}
            \\Screen: {}x{}
            \\World: {}x{} ({})
        ,
            .{ rl.getFPS(), screen_width, screen_height, world_width, world_height, cell_size },
        ) catch return;
        rl.drawText(debug_info, 20, 20, font_size, .black);
    }

    fn updateCamera(self: *Game) void {
        screen_width = rl.getScreenWidth();
        screen_height = rl.getScreenHeight();

        self.camera.offset = .{
            .x = @as(f32, @floatFromInt(screen_width)) / 2,
            .y = @as(f32, @floatFromInt(screen_height)) / 2,
        };
        self.camera.target = .{
            .x = world_width / 2,
            .y = world_height / 2,
        };

        // Take the average between the ratios
        // This avoids "cheating" by changing the ratio to an extreme value
        // in order to see more terrain in a certain axis
        const width_ratio = @as(f32, @floatFromInt(screen_width)) / world_width;
        const height_ratio = @as(f32, @floatFromInt(screen_height)) / world_height;
        self.camera.zoom = (width_ratio + height_ratio) / 2;
    }
};
