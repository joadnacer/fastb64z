const std = @import("std");

const fastb64 = @import("fastb64.zig");

const num_iters = 1000;
const num_kb = 1000;

pub fn main() !void {
    try std.io.getStdOut().writer().print("Time to encode/decode {}KB of unencoded data:\n", .{num_kb});
    try std.io.getStdOut().writer().print("============\n", .{});

    // 1kb * num_kb
    const val = "isg788V6GXbIN8fORdoqyisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfMoUyvDEE9aPisg788V6GXbIN8fORdoqyisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfisg788V6GXbIN8fORdoqyMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfMoUyvDEE9aPsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBfsz6b9liaz5OFzH6r4be94NSDOpEEOk4kamGKt8fL2Qj6ddiOXk7jjfAo8YE5N9GhQTBf" ** num_kb;
    const enc_size = comptime std.base64.standard.Encoder.calcSize(val.len);

    const dec_size = val.len;

    var dec: [dec_size]u8 = undefined;
    var enc: [enc_size]u8 = undefined;

    var begin_time = std.time.nanoTimestamp();

    for (0..num_iters) |_| {
        const res = std.base64.standard.Encoder.encode(&enc, val);

        std.mem.doNotOptimizeAway(res);
    }

    var end_time = std.time.nanoTimestamp();

    try printRes(@divTrunc(end_time - begin_time, num_iters), "std-encode");

    begin_time = std.time.nanoTimestamp();

    for (0..num_iters) |_| {
        const res = fastb64.standard.Encoder.encode(&enc, val);

        std.mem.doNotOptimizeAway(res);
    }

    end_time = std.time.nanoTimestamp();

    try printRes(@divTrunc(end_time - begin_time, num_iters), "fastb64-encode");

    begin_time = std.time.nanoTimestamp();

    for (0..num_iters) |_| {
        try std.base64.standard.Decoder.decode(&dec, &enc);

        std.mem.doNotOptimizeAway(dec);
    }

    end_time = std.time.nanoTimestamp();

    try printRes(@divTrunc(end_time - begin_time, num_iters), "std-decode-validating");

    begin_time = std.time.nanoTimestamp();

    for (0..num_iters) |_| {
        try fastb64.standard.Decoder.decode(&dec, &enc);

        std.mem.doNotOptimizeAway(dec);
    }

    end_time = std.time.nanoTimestamp();

    try printRes(@divTrunc(end_time - begin_time, num_iters), "fastb64-decode-validating");

    begin_time = std.time.nanoTimestamp();

    for (0..num_iters) |_| {
        try fastb64.standard.Decoder.decodeFast(&dec, &enc);

        std.mem.doNotOptimizeAway(dec);
    }

    end_time = std.time.nanoTimestamp();

    try printRes(@divTrunc(end_time - begin_time, num_iters), "fastb64-decode-fast");
}

pub fn printRes(time: i128, tag: []const u8) !void {
    try std.io.getStdOut().writer().print("time={d: >10.2}us test={s}\n", .{
        @as(f32, @floatFromInt(time)) / 1000.0, tag,
    });
}
