const vector_utils = @import("vector_utils.zig");

const ByteVector = vector_utils.ByteVector;
const SignedByteVector = vector_utils.SignedByteVector;

const vec_size8 = vector_utils.vec_size8;

const fromArray = vector_utils.fromArray;
const reinterpret = vector_utils.reinterpret;

pub const DecoderVars = struct {
    shift_lookup: ByteVector,
    mask: ByteVector,
    splat_swap_key: ByteVector,
    splat_swap_val: ByteVector,
};

pub const StandardDecoder: DecoderVars = if (vec_size8 != 0) .{
    .shift_lookup = reinterpret(ByteVector, fromArray(SignedByteVector, &[_]i8{
        0, 0, 19, 4, -65, -65, -71, -71, 0, 0, 0, 0, 0, 0, 0, 0
    } ** 4)),
    .mask = fromArray(ByteVector, &[_]u8{
        0b10101000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000,
        0b11111000, 0b11111000, 0b11110000, 0b01010100, 0b01010000, 0b01010000, 0b01010000, 0b01010100
    } ** 4),
    .splat_swap_key = @splat('/'),
    .splat_swap_val = @splat(16),
} else undefined;

pub const URLDecoder: DecoderVars = if (vec_size8 != 0) .{
    .shift_lookup = reinterpret(ByteVector, fromArray(SignedByteVector, &[_]i8{
        0, 0, 17, 4, -65, -65, -71, -71, 0, 0, 0, 0, 0, 0, 0, 0
    } ** 4)),
    .mask = fromArray(ByteVector, &[_]u8{
        0b10101000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000, 0b11111000,
        0b11111000, 0b11111000, 0b11110000, 0b01010000, 0b01010000, 0b01010100, 0b01010000, 0b01110000
    } ** 4),
    .splat_swap_key = @splat('_'),
    .splat_swap_val = @splat(@bitCast(@as(i8, -32))),
} else undefined;

pub const sp_inc = vec_size8;

pub const dp_inc = if (vec_size8 != 0) @divExact(sp_inc, 4) * 3 else undefined;
