# fastb64z
This a library for encoding/decoding base64 in Zig which makes use of Zig's Vector API, with use of inline assembly for shuffling with a non-comptime mask. This allows for much faster encoding/decoding.

The API was kept as similar to the std base64 as possible, and currently supports RFC4648 standard and URL-safe base64 encoding/decoding with or without padding. A MIME codec will soon be added.

This is currently designed for x86_64 and aarch64 cpus. If used on another cpu, this will fallback to encoding/decoding using the same scalar methods as the standard library.

# Benchmarks
Benchmarks can be run via `zig run -O ReleaseFast src/benchmarks.zig`.

Results of running this on an x86_64 cpu with AVX512 support (512 bit vector length):
```
Time to encode/decode 1000KB of unencoded data:
============
time=    326.16us test=std-encode
time=     43.84us test=fastb64-encode
time=    345.91us test=std-decode-validating
time=     91.02us test=fastb64-decode-validating
time=     81.04us test=fastb64-decode-fast
```

On an aarch64 cpu (128 bit vector length):
```
Time to encode/decode 1000KB of unencoded data:
============
time=    325.52us test=std-encode
time=     96.29us test=fastb64-encode
time=    360.88us test=std-decode-validating
time=    160.30us test=fastb64-decode-validating
time=    119.73us test=fastb64-decode-fast
```

# Usage
Create a build.zig.zon file like this:
```zig
.{
    .name = "example",
    .version = "0.0.1",

    .dependencies = .{
        .fastb64z = .{
            .url = "https://github.com/joadnacer/fastb64z/archive/main.tar.gz",
            .hash = "<hash-here>" },
    },
}
```

Add these lines to your `build.zig`:
```zig
const fastb64z = b.dependency("fastb64z", .{
.target = target,
.optimize = optimize,
});

exe.addModule("fastb64z", fastb64z.module("fastb64z"));
```

Use as follows:
```zig
const fastb64z = @import("fastb64z");

pub fn main() !void {
    // get to_encode/to_decode

    // encodes into enc/res
    const res = fastb64z.standard.Encoder.encode(&enc, to_encode);

    // decodes into dec while validating input
    try fastb64z.standard.Decoder.decode(&dec, &to_decode);

    // decodes into dec while only validating padding/length, not characters
    try fastb64z.standard.Decoder.decodeFast(&dec, &to_decode);
}
```
