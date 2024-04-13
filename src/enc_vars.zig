const vector_utils = @import("vector_utils.zig");

const ByteVector = vector_utils.ByteVector;

const vec_size8 = vector_utils.vec_size8;

const fromArray = vector_utils.fromArray;
const reinterpret = vector_utils.reinterpret;

pub const shift = if (vec_size8 != 0) reinterpret(ByteVector, fromArray(@Vector(vec_size8, i8), &[_]i8{
    'A', '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '+' - 62, '/' - 63, 'a' - 26, 0, 0,
} ** 4)) else undefined;

pub const shift_url = if (vec_size8 != 0) reinterpret(ByteVector, fromArray(@Vector(vec_size8, i8), &[_]i8{
    'A', '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '0' - 52, '-' - 62, '_' - 63, 'a' - 26, 0, 0,
} ** 4)) else undefined;

pub const dp_inc = vec_size8;

pub const sp_inc = if (vec_size8 != 0) @divExact(dp_inc, 4) * 3 else undefined;
