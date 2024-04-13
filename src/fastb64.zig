//! Base64 encoding/decoding.
//! This is a copy of Base64.zig from Zig std modified to use vectorized encoding/decoding.

const std = @import("std");
const builtin = @import("builtin");

const vector64 = @import("vector64.zig");
const vector_utils = @import("vector_utils.zig");
const dec = @import("dec_vars.zig");
const enc = @import("enc_vars.zig");

const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;

const ByteVector = vector_utils.ByteVector;

pub const Error = error{
    InvalidCharacter,
    InvalidPadding,
    NoSpaceLeft,
};

/// Base64 codecs
pub const Codecs = struct {
    alphabet_chars: [64]u8,
    pad_char: ?u8,
    Encoder: Base64Encoder,
    Decoder: Base64Decoder,
};

pub const standard_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".*;

/// Standard Base64 codecs, with padding
pub const standard = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .pad_char = '=',
    .Encoder = Base64Encoder.init(standard_alphabet_chars, enc.shift, '='),
    .Decoder = Base64Decoder.init(standard_alphabet_chars, '=', dec.StandardDecoder),
};

/// Standard Base64 codecs, without padding
pub const standard_no_pad = Codecs{
    .alphabet_chars = standard_alphabet_chars,
    .pad_char = null,
    .Encoder = Base64Encoder.init(standard_alphabet_chars, enc.shift, null),
    .Decoder = Base64Decoder.init(standard_alphabet_chars, null, dec.StandardDecoder),
};

pub const url_safe_alphabet_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".*;

/// URL-safe Base64 codecs, with padding
pub const url_safe = Codecs{
    .alphabet_chars = url_safe_alphabet_chars,
    .pad_char = '=',
    .Encoder = Base64Encoder.init(url_safe_alphabet_chars, enc.shift_url, '='),
    .Decoder = Base64Decoder.init(url_safe_alphabet_chars, '=', dec.URLDecoder),
};

/// URL-safe Base64 codecs, without padding
pub const url_safe_no_pad = Codecs{
    .alphabet_chars = url_safe_alphabet_chars,
    .pad_char = null,
    .Encoder = Base64Encoder.init(url_safe_alphabet_chars, enc.shift_url, null),
    .Decoder = Base64Decoder.init(url_safe_alphabet_chars, null, dec.URLDecoder),
};

const Base64Encoder = struct {
    alphabet_chars: [64]u8,
    shift_lookup: ByteVector,
    pad_char: ?u8,

    /// A bunch of assertions, then simply pass the data right through.
    pub fn init(alphabet_chars: [64]u8, shift_lookup: ByteVector, pad_char: ?u8) Base64Encoder {
        assert(alphabet_chars.len == 64);
        var char_in_alphabet = [_]bool{false} ** 256;
        for (alphabet_chars) |c| {
            assert(!char_in_alphabet[c]);
            assert(pad_char == null or c != pad_char.?);
            char_in_alphabet[c] = true;
        }
        return Base64Encoder{
            .alphabet_chars = alphabet_chars,
            .shift_lookup = shift_lookup,
            .pad_char = pad_char,
        };
    }

    /// Compute the encoded length
    pub fn calcSize(encoder: *const Base64Encoder, source_len: usize) usize {
        if (encoder.pad_char != null) {
            return @divTrunc(source_len + 2, 3) * 4;
        } else {
            const leftover = source_len % 3;
            return @divTrunc(source_len, 3) * 4 + @divTrunc(leftover * 4 + 2, 3);
        }
    }

    /// dest.len must at least be what you get from ::calcSize.
    pub fn encode(encoder: *const Base64Encoder, dest: []u8, source: []const u8) []const u8 {
        const out_len = encoder.calcSize(source.len);
        assert(dest.len >= out_len);

        var idx: usize = 0;
        var out_idx: usize = 0;

        if (comptime vector_utils.vec_size8 != 0) {
            while (idx + vector_utils.vec_size8 < source.len) : ({
                idx += enc.sp_inc;
                out_idx += enc.dp_inc;
            }) {
                vector64.encodeBytesVectorized(source, dest, encoder.shift_lookup, idx, out_idx);
            }
        }
        while (idx + 15 < source.len) : ({
            idx += 12;
            out_idx += 16;
        }) {
            const bits = std.mem.readInt(u128, source[idx..][0..16], .big);
            inline for (0..16) |i| {
                dest[out_idx + i] = encoder.alphabet_chars[@truncate((bits >> (122 - i * 6)) & 0x3f)];
            }
        }
        while (idx + 3 < source.len) : ({
            idx += 3;
            out_idx += 4;
        }) {
            const bits = std.mem.readInt(u32, source[idx..][0..4], .big);
            dest[out_idx] = encoder.alphabet_chars[(bits >> 26) & 0x3f];
            dest[out_idx + 1] = encoder.alphabet_chars[(bits >> 20) & 0x3f];
            dest[out_idx + 2] = encoder.alphabet_chars[(bits >> 14) & 0x3f];
            dest[out_idx + 3] = encoder.alphabet_chars[(bits >> 8) & 0x3f];
        }

        if (idx + 2 < source.len) {
            dest[out_idx] = encoder.alphabet_chars[source[idx] >> 2];
            dest[out_idx + 1] = encoder.alphabet_chars[((source[idx] & 0x3) << 4) | (source[idx + 1] >> 4)];
            dest[out_idx + 2] = encoder.alphabet_chars[(source[idx + 1] & 0xf) << 2 | (source[idx + 2] >> 6)];
            dest[out_idx + 3] = encoder.alphabet_chars[source[idx + 2] & 0x3f];
            out_idx += 4;
        } else if (idx + 1 < source.len) {
            dest[out_idx] = encoder.alphabet_chars[source[idx] >> 2];
            dest[out_idx + 1] = encoder.alphabet_chars[((source[idx] & 0x3) << 4) | (source[idx + 1] >> 4)];
            dest[out_idx + 2] = encoder.alphabet_chars[(source[idx + 1] & 0xf) << 2];
            out_idx += 3;
        } else if (idx < source.len) {
            dest[out_idx] = encoder.alphabet_chars[source[idx] >> 2];
            dest[out_idx + 1] = encoder.alphabet_chars[(source[idx] & 0x3) << 4];
            out_idx += 2;
        }

        if (encoder.pad_char) |pad_char| {
            for (dest[out_idx..out_len]) |*pad| {
                pad.* = pad_char;
            }
        }

        return dest[0..out_len];
    }
};

pub const Base64Decoder = struct {
    const invalid_char: u8 = 0xff;
    const invalid_char_tst: u32 = 0xff000000;

    /// e.g. 'A' => 0.
    /// `invalid_char` for any value not in the 64 alphabet chars.
    char_to_index: [256]u8,
    fast_char_to_index: [4][256]u32,
    vec_vars: dec.DecoderVars,
    pad_char: ?u8,

    pub fn init(alphabet_chars: [64]u8, pad_char: ?u8, vec_vars: dec.DecoderVars) Base64Decoder {
        var result = Base64Decoder{
            .char_to_index = [_]u8{invalid_char} ** 256,
            .fast_char_to_index = .{[_]u32{invalid_char_tst} ** 256} ** 4,
            .vec_vars = vec_vars,
            .pad_char = pad_char,
        };

        var char_in_alphabet = [_]bool{false} ** 256;
        for (alphabet_chars, 0..) |c, i| {
            assert(!char_in_alphabet[c]);
            assert(pad_char == null or c != pad_char.?);

            const ci = @as(u32, @intCast(i));
            result.fast_char_to_index[0][c] = ci << 2;
            result.fast_char_to_index[1][c] = (ci >> 4) | ((ci & 0x0f) << 12);
            result.fast_char_to_index[2][c] = ((ci & 0x3) << 22) | ((ci & 0x3c) << 6);
            result.fast_char_to_index[3][c] = ci << 16;

            result.char_to_index[c] = @as(u8, @intCast(i));
            char_in_alphabet[c] = true;
        }
        return result;
    }

    /// Return the maximum possible decoded size for a given input length - The actual length may be less if the input includes padding.
    /// `InvalidPadding` is returned if the input length is not valid.
    pub fn calcSizeUpperBound(decoder: *const Base64Decoder, source_len: usize) Error!usize {
        var result = source_len / 4 * 3;
        const leftover = source_len % 4;
        if (decoder.pad_char != null) {
            if (leftover % 4 != 0) return error.InvalidPadding;
        } else {
            if (leftover % 4 == 1) return error.InvalidPadding;
            result += leftover * 3 / 4;
        }
        return result;
    }

    /// Return the exact decoded size for a slice.
    /// `InvalidPadding` is returned if the input length is not valid.
    pub fn calcSizeForSlice(decoder: *const Base64Decoder, source: []const u8) Error!usize {
        const source_len = source.len;
        var result = try decoder.calcSizeUpperBound(source_len);
        if (decoder.pad_char) |pad_char| {
            if (source_len >= 1 and source[source_len - 1] == pad_char) result -= 1;
            if (source_len >= 2 and source[source_len - 2] == pad_char) result -= 1;
        }
        return result;
    }

    /// dest.len must be what you get from ::calcSize.
    /// Invalid characters result in `error.InvalidCharacter`.
    /// Invalid padding results in `error.InvalidPadding`.
    pub fn decode(decoder: *const Base64Decoder, dest: []u8, source: []const u8) Error!void {
        if (decoder.pad_char != null and source.len % 4 != 0) return error.InvalidPadding;
        var dest_idx: usize = 0;
        var fast_src_idx: usize = 0;
        var acc: u12 = 0;
        var acc_len: u4 = 0;
        var leftover_idx: ?usize = null;

        if (comptime vector_utils.vec_size8 != 0) {
            while (dest_idx + vector_utils.vec_size8 < dest.len) : ({
                fast_src_idx += dec.sp_inc;
                dest_idx += dec.dp_inc;
            }) {
                try vector64.decodeBytesVectorizedValidating(source, dest, decoder.vec_vars, fast_src_idx, dest_idx);
            }
        }
        while (fast_src_idx + 16 < source.len and dest_idx + 15 < dest.len) : ({
            fast_src_idx += 16;
            dest_idx += 12;
        }) {
            var bits: u128 = 0;
            inline for (0..4) |i| {
                var new_bits: u128 = decoder.fast_char_to_index[0][source[fast_src_idx + i * 4]];
                new_bits |= decoder.fast_char_to_index[1][source[fast_src_idx + 1 + i * 4]];
                new_bits |= decoder.fast_char_to_index[2][source[fast_src_idx + 2 + i * 4]];
                new_bits |= decoder.fast_char_to_index[3][source[fast_src_idx + 3 + i * 4]];
                if ((new_bits & invalid_char_tst) != 0) return error.InvalidCharacter;
                bits |= (new_bits << (24 * i));
            }
            std.mem.writeInt(u128, dest[dest_idx..][0..16], bits, .little);
        }
        while (fast_src_idx + 4 < source.len and dest_idx + 3 < dest.len) : ({
            fast_src_idx += 4;
            dest_idx += 3;
        }) {
            var bits = decoder.fast_char_to_index[0][source[fast_src_idx]];
            bits |= decoder.fast_char_to_index[1][source[fast_src_idx + 1]];
            bits |= decoder.fast_char_to_index[2][source[fast_src_idx + 2]];
            bits |= decoder.fast_char_to_index[3][source[fast_src_idx + 3]];
            if ((bits & invalid_char_tst) != 0) return error.InvalidCharacter;
            std.mem.writeInt(u32, dest[dest_idx..][0..4], bits, .little);
        }
        const remaining = source[fast_src_idx..];
        for (remaining, fast_src_idx..) |c, src_idx| {
            const d = decoder.char_to_index[c];
            if (d == invalid_char) {
                if (decoder.pad_char == null or c != decoder.pad_char.?) return error.InvalidCharacter;
                leftover_idx = src_idx;
                break;
            }
            acc = (acc << 6) + d;
            acc_len += 6;
            if (acc_len >= 8) {
                acc_len -= 8;
                dest[dest_idx] = @as(u8, @truncate(acc >> acc_len));
                dest_idx += 1;
            }
        }
        if (acc_len > 4 or (acc & (@as(u12, 1) << acc_len) - 1) != 0) {
            return error.InvalidPadding;
        }
        if (leftover_idx == null) return;
        const leftover = source[leftover_idx.?..];
        if (decoder.pad_char) |pad_char| {
            const padding_len = acc_len / 2;
            var padding_chars: usize = 0;
            for (leftover) |c| {
                if (c != pad_char) {
                    return if (c == Base64Decoder.invalid_char) error.InvalidCharacter else error.InvalidPadding;
                }
                padding_chars += 1;
            }
            if (padding_chars != padding_len) return error.InvalidPadding;
        }
    }

    /// dest.len must be what you get from ::calcSize.
    /// validates padding but does not validate characters (except where padding should be)
    pub fn decodeFast(decoder: *const Base64Decoder, dest: []u8, source: []const u8) Error!void {
        if (decoder.pad_char != null and source.len % 4 != 0) return error.InvalidPadding;
        var dest_idx: usize = 0;
        var fast_src_idx: usize = 0;
        var acc: u12 = 0;
        var acc_len: u4 = 0;
        var leftover_idx: ?usize = null;

        if (comptime vector_utils.vec_size8 != 0) {
            while (dest_idx + vector_utils.vec_size8 < dest.len) : ({
                fast_src_idx += dec.sp_inc;
                dest_idx += dec.dp_inc;
            }) {
                vector64.decodeBytesVectorized(source, dest, decoder.vec_vars, fast_src_idx, dest_idx);
            }
        }
        while (fast_src_idx + 16 < source.len and dest_idx + 15 < dest.len) : ({
            fast_src_idx += 16;
            dest_idx += 12;
        }) {
            var bits: u128 = 0;
            inline for (0..4) |i| {
                var new_bits: u128 = decoder.fast_char_to_index[0][source[fast_src_idx + i * 4]];
                new_bits |= decoder.fast_char_to_index[1][source[fast_src_idx + 1 + i * 4]];
                new_bits |= decoder.fast_char_to_index[2][source[fast_src_idx + 2 + i * 4]];
                new_bits |= decoder.fast_char_to_index[3][source[fast_src_idx + 3 + i * 4]];
                bits |= (new_bits << (24 * i));
            }
            std.mem.writeInt(u128, dest[dest_idx..][0..16], bits, .little);
        }
        while (fast_src_idx + 4 < source.len and dest_idx + 3 < dest.len) : ({
            fast_src_idx += 4;
            dest_idx += 3;
        }) {
            var bits = decoder.fast_char_to_index[0][source[fast_src_idx]];
            bits |= decoder.fast_char_to_index[1][source[fast_src_idx + 1]];
            bits |= decoder.fast_char_to_index[2][source[fast_src_idx + 2]];
            bits |= decoder.fast_char_to_index[3][source[fast_src_idx + 3]];
            std.mem.writeInt(u32, dest[dest_idx..][0..4], bits, .little);
        }
        const remaining = source[fast_src_idx..];
        for (remaining, fast_src_idx..) |c, src_idx| {
            const d = decoder.char_to_index[c];
            if (d == invalid_char) {
                leftover_idx = src_idx;
                break;
            }
            acc = (acc << 6) + d;
            acc_len += 6;
            if (acc_len >= 8) {
                acc_len -= 8;
                dest[dest_idx] = @as(u8, @truncate(acc >> acc_len));
                dest_idx += 1;
            }
        }
        if (acc_len > 4 or (acc & (@as(u12, 1) << acc_len) - 1) != 0) {
            return error.InvalidPadding;
        }
        if (leftover_idx == null) return;
        const leftover = source[leftover_idx.?..];
        if (decoder.pad_char) |pad_char| {
            const padding_len = acc_len / 2;
            var padding_chars: usize = 0;
            for (leftover) |c| {
                if (c != pad_char) {
                    return if (c == Base64Decoder.invalid_char) error.InvalidCharacter else error.InvalidPadding;
                }
                padding_chars += 1;
            }
            if (padding_chars != padding_len) return error.InvalidPadding;
        }
    }
};

test "base64" {
    @setEvalBranchQuota(8000);
    try testBase64();
    try comptime testAllApis(standard, "comptime", "Y29tcHRpbWU=");
}

test "base64 padding dest overflow" {
    const input = "foo";

    var expect: [128]u8 = undefined;
    @memset(&expect, 0);
    _ = url_safe.Encoder.encode(expect[0..url_safe.Encoder.calcSize(input.len)], input);

    var got: [128]u8 = undefined;
    @memset(&got, 0);
    _ = url_safe.Encoder.encode(&got, input);

    try std.testing.expectEqualSlices(u8, &expect, &got);
}

test "base64 url_safe_no_pad" {
    @setEvalBranchQuota(8000);
    try testBase64UrlSafeNoPad();
    try comptime testAllApis(url_safe_no_pad, "comptime", "Y29tcHRpbWU");
}

fn testBase64() !void {
    const codecs = standard;

    // test long input for vector
    const base_raw = "foobar" ** 16;
    const base_enc = "Zm9vYmFy" ** 16;

    try testAllApis(codecs, "", "");
    try testAllApis(codecs, base_raw, base_enc);
    try testAllApis(codecs, base_raw ++ "f", base_enc ++ "Zg==");
    try testAllApis(codecs, base_raw ++ "fo", base_enc ++ "Zm8=");
    try testAllApis(codecs, base_raw ++ "foo", base_enc ++ "Zm9v");
    try testAllApis(codecs, base_raw ++ "foob", base_enc ++ "Zm9vYg==");
    try testAllApis(codecs, base_raw ++ "fooba", base_enc ++ "Zm9vYmE=");
    try testAllApis(codecs, base_raw ++ "foobar", base_enc ++ "Zm9vYmFy");

    // test getting some api errors
    try testError(codecs, "A", error.InvalidPadding);
    try testError(codecs, "AA", error.InvalidPadding);
    try testError(codecs, "AAA", error.InvalidPadding);
    try testError(codecs, "A..A", error.InvalidCharacter);
    try testError(codecs, "AA=A", error.InvalidPadding);
    try testError(codecs, "AA/=", error.InvalidPadding);
    try testError(codecs, "A/==", error.InvalidPadding);
    try testError(codecs, "A===", error.InvalidPadding);
    try testError(codecs, "====", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vYmFyA..A", error.InvalidCharacter);
    try testError(codecs, "Zm9vYmFyZm9vYmFyAA=A", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vYmFyAA/=", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vYmFyA/==", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vYmFyA===", error.InvalidPadding);
    try testError(codecs, "A..AZm9vYmFyZm9vYmFy", error.InvalidCharacter);
    try testError(codecs, "Zm9vYmFyZm9vAA=A", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vAA/=", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vA/==", error.InvalidPadding);
    try testError(codecs, "Zm9vYmFyZm9vA===", error.InvalidPadding);
    try testError(codecs, "AAA=" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A..A" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "AA=A" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "AA/=" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A/==" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A===" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "====" ++ base_enc, error.InvalidCharacter);
}

fn testBase64UrlSafeNoPad() !void {
    const codecs = url_safe_no_pad;

    // test long input for vector
    const base_raw = "foobar" ** 16;
    const base_enc = "Zm9vYmFy" ** 16;

    try testAllApis(codecs, "", "");
    try testAllApis(codecs, base_raw, base_enc);
    try testAllApis(codecs, base_raw ++ "f", base_enc ++ "Zg");
    try testAllApis(codecs, base_raw ++ "fo", base_enc ++ "Zm8");
    try testAllApis(codecs, base_raw ++ "foo", base_enc ++ "Zm9v");
    try testAllApis(codecs, base_raw ++ "foob", base_enc ++ "Zm9vYg");
    try testAllApis(codecs, base_raw ++ "fooba", base_enc ++ "Zm9vYmE");
    try testAllApis(codecs, base_raw ++ "foobar", base_enc ++ "Zm9vYmFy");
    try testAllApis(codecs, base_raw ++ "foobarfoobarfoobar", base_enc ++ "Zm9vYmFyZm9vYmFyZm9vYmFy");

    // test getting some api errors
    try testError(codecs, "A", error.InvalidPadding);
    try testError(codecs, "AAA=", error.InvalidCharacter);
    try testError(codecs, "A..A", error.InvalidCharacter);
    try testError(codecs, "AA=A", error.InvalidCharacter);
    try testError(codecs, "AA/=", error.InvalidCharacter);
    try testError(codecs, "A/==", error.InvalidCharacter);
    try testError(codecs, "A===", error.InvalidCharacter);
    try testError(codecs, "====", error.InvalidCharacter);
    try testError(codecs, "Zm9vYmFyZm9vYmFyA..A", error.InvalidCharacter);
    try testError(codecs, "A..AZm9vYmFyZm9vYmFy", error.InvalidCharacter);
    try testError(codecs, "AAA=" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A..A" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "AA=A" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "AA/=" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A/==" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "A===" ++ base_enc, error.InvalidCharacter);
    try testError(codecs, "====" ++ base_enc, error.InvalidCharacter);
}

fn testAllApis(codecs: Codecs, comptime expected_decoded: []const u8, comptime expected_encoded: []const u8) !void {
    // Base64Encoder
    {
        var buffer: [expected_encoded.len]u8 = undefined;
        const encoded = codecs.Encoder.encode(&buffer, expected_decoded);
        try testing.expectEqualSlices(u8, expected_encoded, encoded);
    }

    // Base64Decoder
    {
        var buffer: [expected_decoded.len]u8 = undefined;
        const decoded = buffer[0..try codecs.Decoder.calcSizeForSlice(expected_encoded)];
        try codecs.Decoder.decodeFast(decoded, expected_encoded);
        try testing.expectEqualSlices(u8, expected_decoded, decoded);
    }
}

fn testError(codecs: Codecs, encoded: []const u8, expected_err: anyerror) !void {
    var buffer: [0x100]u8 = undefined;
    if (codecs.Decoder.calcSizeForSlice(encoded)) |decoded_size| {
        const decoded = buffer[0..decoded_size];
        if (codecs.Decoder.decode(decoded, encoded)) |_| {
            return error.ExpectedError;
        } else |err| if (err != expected_err) return err;
    } else |err| if (err != expected_err) return err;
}
