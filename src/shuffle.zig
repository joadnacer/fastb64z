const std = @import("std");
const builtin = @import("builtin");

const vector_utils = @import("vector_utils.zig");

const assert = std.debug.assert;

const vec_size8 = vector_utils.vec_size8;

const ByteVector = vector_utils.ByteVector;

inline fn shuffle(src: ByteVector, mask: ByteVector) ByteVector {
    return asm ("vpshufb %[mask], %[src], %[dst]"
        : [dst] "=x" (-> ByteVector),
        : [src] "x" (src),
          [mask] "x" (mask),
    );
}

inline fn lookup_16_aarch64(x: @Vector(16, u8), mask: @Vector(16, u8)) @Vector(16, u8) {
    return asm (
        \\tbl  %[out].16b, {%[mask].16b}, %[x].16b
        : [out] "=&x" (-> @Vector(16, u8)),
        : [x] "x" (x),
          [mask] "x" (mask),
    );
}

pub inline fn lookup_ByteVector(a: ByteVector, b: ByteVector) ByteVector {
    switch (builtin.cpu.arch) {
        .x86_64 => return shuffle(a, b),
        .aarch64, .aarch64_be => return lookup_16_aarch64(b, a),
        else => {
            var r: ByteVector = @splat(0);

            for (0..vec_size8) |i| {
                const c = b[i];
                assert(c <= 0x0F);
                r[i] = a[c];
            }

            return r;
        },
    }
}
