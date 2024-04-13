const std = @import("std");

const shuffle = @import("shuffle.zig");
const vector_utils = @import("vector_utils.zig");
const dec_vars = @import("dec_vars.zig");
const fastb64 = @import("fastb64.zig");

const Error = fastb64.Error;

const assert = std.debug.assert;

const vec_size8 = vector_utils.vec_size8;
const vec_size16 = vector_utils.vec_size16;
const vec_size32 = vector_utils.vec_size32;

const ByteVector = vector_utils.ByteVector;
const ShortVector = vector_utils.ShortVector;
const IntVector = vector_utils.IntVector;

const DecoderVars = dec_vars.DecoderVars;

const fromArray = vector_utils.fromArray;
const reinterpret = vector_utils.reinterpret;
const reinterpretSplat = vector_utils.reinterpretSplat;

const enc_shuffle = fromArray(ByteVector, &[_]u8{
    1, 0, 2, 1, 4, 3, 5, 4, 7, 6, 8, 7, 10, 9, 11, 10, 13, 12, 14, 13, 16, 15, 17, 16, 19, 18, 20,
    19, 22, 21, 23, 22, 25, 24, 26, 25, 28, 27, 29, 28, 31, 30, 32, 31, 34, 33, 35, 34, 37, 36, 38,
    37, 40, 39, 41, 40, 43, 42, 44, 43, 46, 45, 47, 46, 49, 48, 50, 49
});

const ac_mask = reinterpretSplat(ShortVector, u32, 0x0fc0fc00);
const ac_shift = reinterpretSplat(ShortVector, u32, 0x0006000a);

const bd_mask = reinterpretSplat(ShortVector, u32, 0x003f03f0);
const bd_shift = reinterpretSplat(ShortVector, u32, 0x00080004);

const dec_pack: ByteVector = switch (vec_size8) {
    16 => fromArray(ByteVector, &[_]u8{
        2, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 0, 0, 0, 0
    }),
    32 => fromArray(ByteVector, &[_]u8{
        2, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 18, 17, 16, 22, 21, 20, 26, 25, 24, 30, 29, 28, 0,
        0, 0, 0, 0, 0, 0, 0
    }),
    64 => fromArray(ByteVector, &[_]u8{
        2, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 18, 17, 16, 22, 21, 20, 26, 25, 24, 30, 29, 28, 34,
        33, 32, 38, 37, 36, 42, 41, 40, 46, 45, 44, 50, 49, 48, 54, 53, 52, 58, 57, 56, 62, 61, 60,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    }),
    else => @panic("Vector type unsupported"),
};

const bit_pos_lut = fromArray(ByteVector, &[_]u8{
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0, 0, 0, 0, 0, 0, 0, 0
} ** 4);

const splat0: ByteVector = @splat(0);
const splat4: ByteVector = @splat(4);
const splat13: ByteVector = @splat(13);
const splat26: ByteVector = @splat(26);
const splat51: ByteVector = @splat(51);
const splat52: ByteVector = @splat(52);

const splat_0x0f: ByteVector = @splat(0x0f);

const splat6: IntVector = @splat(6);
const splat8: IntVector = @splat(8);
const splat12: IntVector = @splat(12);
const splat16: IntVector = @splat(16);

const splat_0x003f003f: IntVector = @splat(0x003f003f);
const splat_0x3f003f00: IntVector = @splat(0x3f003f00);

pub fn encodeBytesVectorized(src: []const u8, dst: []u8, shift_lookup: ByteVector, sp: usize, dp: usize) void {
    const input = fromArray(ByteVector, src[sp .. sp + vec_size8]);
    const shuffled = @shuffle(u8, input, undefined, enc_shuffle);
    const short_shuffled = reinterpret(ShortVector, shuffled);

    const ac = short_shuffled & ac_mask;
    const bd = short_shuffled & bd_mask;

    const ac_shifted = ac >> ac_shift;
    const bd_shifted = bd << bd_shift;

    const no_lookup_res = reinterpret(ByteVector, ac_shifted | bd_shifted);

    const gte26 = no_lookup_res >= splat26;
    const lt52 = no_lookup_res < splat52;

    const thirteens = @select(bool, lt52, gte26, lt52);

    const subbed = @subWithOverflow(no_lookup_res, splat51).@"0";
    const subbed_masked = subbed ^ @select(u8, lt52, subbed, splat0);
    const subbed_thirteens = @select(u8, thirteens, splat13, subbed_masked);

    const shifts = shuffle.lookup_ByteVector(shift_lookup, subbed_thirteens);

    const res = @addWithOverflow(no_lookup_res, shifts).@"0";
    const res_arr: [vec_size8]u8 = res;

    @memcpy(dst[dp .. dp + vec_size8], res_arr[0..]);
}

pub fn decodeBytesVectorized(src: []const u8, dst: []u8, vars: DecoderVars, sp: usize, dp: usize) void {
    const input = fromArray(ByteVector, src[sp .. sp + vec_size8]);

    const high_nibble = input >> splat4;

    const sh = shuffle.lookup_ByteVector(vars.shift_lookup, high_nibble);
    const eq_swap = input == vars.splat_swap_key;
    const shift = @select(u8, eq_swap, vars.splat_swap_val, sh);

    const shifted = reinterpret(IntVector, @addWithOverflow(input, shift).@"0");

    const ca = shifted & splat_0x003f003f;
    const db = shifted & splat_0x3f003f00;

    const t0 = (db >> splat8) | (ca << splat6);
    const t1 = (t0 >> splat16) | (t0 << splat12);

    const t1_byte = reinterpret(ByteVector, t1);

    const res = @shuffle(u8, t1_byte, undefined, dec_pack);
    const res_arr: [vec_size8]u8 = res;

    @memcpy(dst[dp .. dp + vec_size8], res_arr[0..]);
}

pub fn decodeBytesVectorizedValidating(src: []const u8, dst: []u8, vars: DecoderVars, sp: usize, dp: usize) Error!void {
    const input = fromArray(ByteVector, src[sp .. sp + vec_size8]);

    const high_nibble = input >> splat4;
    const low_nibble = input & splat_0x0f;

    const sh = shuffle.lookup_ByteVector(vars.shift_lookup, high_nibble);
    const eq_swap = input == vars.splat_swap_key;
    const shift = @select(u8, eq_swap, vars.splat_swap_val, sh);

    const masked = shuffle.lookup_ByteVector(vars.mask, low_nibble);
    const bit = shuffle.lookup_ByteVector(bit_pos_lut, high_nibble);
    const masked_and_bit = masked & bit;

    if (@reduce(.Or, masked_and_bit == splat0)) {
        return error.InvalidCharacter;
    }

    const shifted = reinterpret(IntVector, @addWithOverflow(input, shift).@"0");

    const ca = shifted & splat_0x003f003f;
    const db = shifted & splat_0x3f003f00;

    const t0 = (db >> splat8) | (ca << splat6);
    const t1 = (t0 >> splat16) | (t0 << splat12);

    const t1_byte = reinterpret(ByteVector, t1);

    const res = @shuffle(u8, t1_byte, undefined, dec_pack);
    const res_arr: [vec_size8]u8 = res;

    @memcpy(dst[dp .. dp + vec_size8], res_arr[0..]);
}
