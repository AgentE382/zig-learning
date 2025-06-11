//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // Don't forget to flush!
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

            pixels[row * imgSize[0] + col] = switch (escapeCount) {
                null => 0,
                else => 255 - escapeCount.?,
            };
        }
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
