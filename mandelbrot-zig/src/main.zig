//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 5) {
        std.log.err("Usage: {s} [IMAGE_FILE] [IMAGE_RESOLUTION] [MANDELBROT_TOP_LEFT] [MANDELBROT_BOTTOM_RIGHT]\nExample: {s} mandelbrot.png 1000x750 -1.20,0.35 -1,0.20", .{ args[0], args[0] });
        std.process.exit(1);
    }

    const imgSize = if (parseArg(usize, args[2], 'x')) |s| s else {
        std.log.err("Failed to parse image resolution", .{});
        return;
    };
    const topLeft = if (parseComplex(f64, args[3])) |p| p else {
        std.log.err("Failed to parse top left point", .{});
        return;
    };
    const bottomRight = if (parseComplex(f64, args[4])) |p| p else {
        std.log.err("Failed to parse bottom right point", .{});
        return;
    };

    const pixels = try allocator.alloc(u8, imgSize[0] * imgSize[1]);
    defer allocator.free(pixels);

    // Calculate the number of rows each thread should process based on CPU count.
    const threadCount = try std.Thread.getCpuCount();
    var threads = try allocator.alloc(std.Thread, threadCount);
    defer allocator.free(threads);
    const rowsPerBand = imgSize[1] / threadCount + 1;

    // Create and start threads, each processing a segment of the image.
    for (0..threadCount) |i| {
        // Determine the portion of the image array this thread will handle.
        const band = pixels[i * rowsPerBand * imgSize[0] .. @min((i + 1) * rowsPerBand * imgSize[0], pixels.len)];
        const top = i * rowsPerBand;
        const height = band.len / imgSize[0];
        const bandSize = .{ imgSize[0], height };

        const bandTopLeft = pixelToPoint(imgSize, .{ 0, top }, topLeft, bottomRight);
        const bandBottomRight = pixelToPoint(imgSize, .{ imgSize[0], top + height }, topLeft, bottomRight);

        // Spawn a new thread to process this part of the image.
        threads[i] = try std.Thread.spawn(.{}, render, .{ band, bandSize, bandTopLeft, bandBottomRight });
    }

    // Ensure all threads complete their tasks.
    for (threads) |thread| {
        thread.join();
    }
    try writeImage(args[1], pixels, imgSize);
}

fn squareAdd(c: f64, n: u32) f64 {
    var z: f64 = 0;
    for (0..n) |_| {
        z = z * z + c;
    }
    return z;
}

fn Complex(comptime T: type) type {
    return struct {
        const Self = @This();

        re: T,
        im: T,

        /// Adds two complex numbers
        fn add(self: Self, other: Self) Self {
            return Complex(T){
                .re = self.re + other.re,
                .im = self.im + other.im,
            };
        }

        /// Multiplies two complex numbers
        fn multiply(self: Self, other: Self) Self {
            return Complex(T){
                .re = self.re * other.re - self.im * other.im,
                .im = self.re * other.im + self.im * other.re,
            };
        }

        /// Computes the squared norm of the complex number
        fn normSqr(self: Self) T {
            return self.re * self.re + self.im * self.im;
        }
    };
}

fn escapeTime(c: Complex(f64), limit: usize) ?usize {
    var z = Complex(f64){ .re = 0.0, .im = 0.0 };
    for (0..limit) |i| {
        if (z.normSqr() > 4.0) {
            return i;
        }
        z = z.multiply(z).add(c);
    }
    return null;
}

fn pixelToPoint(imgSize: [2]usize, pixel: [2]usize, pointTopLeft: Complex(f64), pointBottomRight: Complex(f64)) Complex(f64) {
    const width = pointBottomRight.re - pointTopLeft.re;
    const height = pointTopLeft.im - pointBottomRight.im;
    return Complex(f64){
        // Calculate the real part of the complex number.
        .re = pointTopLeft.re + @as(f64, @floatFromInt(pixel[0])) * width / @as(f64, @floatFromInt(imgSize[0])),

        // Calculate the imaginary part of the complex number.
        // Subtract here because in image coordinates, y increases as you go down,
        // but in the complex plane, the imaginary part increases as you go up.
        .im = pointTopLeft.im - @as(f64, @floatFromInt(pixel[1])) * height / @as(f64, @floatFromInt(imgSize[1])),
    };
}

fn render(pixels: []u8, imgSize: [2]usize, pointTopLeft: Complex(f64), pointBottomRight: Complex(f64)) void {
    for (0..imgSize[1]) |row| {
        for (0..imgSize[0]) |col| {
            const point = pixelToPoint(imgSize, .{ col, row }, pointTopLeft, pointBottomRight);
            const escapeCount = escapeTime(point, 255);

            pixels[row * imgSize[0] + col] = if (escapeCount) |count| 255 - @as(u8, @intCast(count)) else 0;
        }
    }
}

fn writeImage(filename: []const u8, pixels: []const u8, imgSize: [2]usize) !void {
    const width = imgSize[0];
    const height = imgSize[1];
    const allocator = std.heap.page_allocator;

    // Initialize image object with given pixel data and configuration.
    const pixelStorage = try zigimg.color.PixelStorage.init(allocator, zigimg.PixelFormat.grayscale8, width * height);

    for (pixels, 0..) |pixel, index| {
        pixelStorage.grayscale8[index] = zigimg.color.Grayscale8{ .value = pixel };
    }

    var image = zigimg.Image{
        .allocator = allocator,
        .width = width,
        .height = height,
        .pixels = pixelStorage,
    };

    defer image.deinit();

    try image.writeToFilePath(filename, zigimg.Image.EncoderOptions{ .png = .{} });
}

fn parseArg(comptime T: type, str: []const u8, separator: u8) ?[2]T {
    if (str.len == 0) return null;

    const index = std.mem.indexOfScalar(u8, str, separator);

    if (index) |i| {
        const leftStr = str[0..i];
        const rightStr = str[i + 1 ..];

        const left = parseT(T, leftStr) catch return null;
        const right = parseT(T, rightStr) catch return null;

        return [2]T{ left, right };
    } else return null;
}

fn parseT(comptime T: type, str: []const u8) !T {
    switch (T) {
        f32, f64 => {
            return std.fmt.parseFloat(T, str);
        },
        i32, i64, usize => {
            return std.fmt.parseInt(T, str, 10);
        },
        else => {
            @compileError("Unsupported type for parseT");
        },
    }
}

fn parseComplex(comptime T: type, str: []const u8) ?Complex(T) {
    const maybePair = parseArg(T, str, ',');

    if (maybePair) |pair| {
        return Complex(T){ .re = pair[0], .im = pair[1] };
    } else {
        return null;
    }
}

test "expect pont escapes the Mandelbrot set" {
    const limit = 1000;
    const c = Complex(f64){ .re = 1.0, .im = 1.0 };
    const result = escapeTime(c, limit);
    try std.testing.expect(result != null);
}

test "expect point stays within the Mandelbrot set" {
    const limit = 1000;
    const c = Complex(f64){ .re = 0.0, .im = 0.0 };
    const result = escapeTime(c, limit);
    try std.testing.expect(result == null);
}

test "expect pixel maps to point on the complex plane" {
    const topLeft = Complex(f64){ .re = -1.0, .im = 1.0 };
    const bottomRight = Complex(f64){ .re = 1.0, .im = -1.0 };
    const result = pixelToPoint(.{ 100, 200 }, .{ 25, 175 }, topLeft, bottomRight);
    try std.testing.expectEqual(Complex(f64){ .re = -0.5, .im = -0.75 }, result);
}

test "expect argument parsed as proper type" {
    try std.testing.expectEqual([2]i32{ 100, 200 }, parseArg(i32, "100x200", 'x'));
    try std.testing.expectEqual([2]f64{ -2.0, 0.5 }, parseArg(f64, "-2.0,0.5", ','));
    try std.testing.expectEqual(null, parseArg(f64, "x0.2", 'x'));
    try std.testing.expectEqual(null, parseArg(i32, "ab10,7c", ','));
    try std.testing.expectEqual(null, parseArg(i32, "7,", ','));
    try std.testing.expectEqual(null, parseArg(i32,",7", ','));
    try std.testing.expectEqual(null, parseArg(i32, "", ','));
}

test "expect string is parsed into complex number" {
    try std.testing.expectEqual(Complex(f64){ .re = -2.0, .im = 0.5 }, parseComplex(f64, "-2.0,0.5"));
    try std.testing.expectEqual(null, parseComplex(f64, "-2.0,"));
}


test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");
const zigimg = @import("zigimg");
