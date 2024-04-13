const std = @import("std");

const assert = std.debug.assert;

// setting vec_size8 to 0 results in only scalar encoding/decoding being used
pub const vec_size8 = std.simd.suggestVectorLength(u8) orelse 0;
pub const vec_size16 = std.simd.suggestVectorLength(u16) orelse 0;
pub const vec_size32 = std.simd.suggestVectorLength(u32) orelse 0;

pub const ByteVector = @Vector(vec_size8, u8);
pub const SignedByteVector = @Vector(vec_size8, i8);
pub const ShortVector = @Vector(vec_size16, u16);
pub const IntVector = @Vector(vec_size32, u32);

pub fn fromArray(comptime ToVector: type, from_array: []const @typeInfo(ToVector).Vector.child) ToVector {
    assert(from_array.len >= @typeInfo(ToVector).Vector.len);

    return from_array[0..@typeInfo(ToVector).Vector.len].*;
}

pub fn reinterpretSplat(comptime ToVector: type, comptime SplatType: type, splat: SplatType) ToVector {
    const to_len = @typeInfo(ToVector).Vector.len;
    const ToType = @typeInfo(ToVector).Vector.child;

    const splat_len = @divExact(@sizeOf(ToType) * to_len, @sizeOf(SplatType));
    const splat_vec: @Vector(splat_len, SplatType) = @splat(splat);

    return reinterpret(ToVector, splat_vec);
}

pub fn reinterpret(comptime ToVector: type, from_vector: anytype) ToVector {
    const from_len = @typeInfo(@TypeOf(from_vector)).Vector.len;
    const FromType = @TypeOf(from_vector[0]);

    const to_len = @typeInfo(ToVector).Vector.len;
    const ToType = @typeInfo(ToVector).Vector.child;

    assert(from_len * @sizeOf(FromType) == to_len * @sizeOf(ToType));

    const underlying_array: [from_len]FromType = from_vector;
    const reinterpreted_array: [to_len]ToType = @as(*[to_len]ToType, @ptrCast(@constCast(@alignCast(&underlying_array)))).*;

    return reinterpreted_array;
}
