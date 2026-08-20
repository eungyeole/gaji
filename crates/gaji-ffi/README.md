# Gaji native API

`gaji-ffi` builds the shared Rust engine as both a static and dynamic library.
The ABI is intentionally tiny: UTF-8 input and owned JSON output through the
functions declared in `include/gaji.h`.

```sh
cargo build -p gaji-ffi --release
```

Every returned pointer belongs to the caller and must be passed to
`gaji_string_free` exactly once. Responses have this envelope:

```json
{"ok":true,"value":{}}
```

Failures use `{ "ok": false, "error": "..." }`. This keeps Swift and C# model
decoding stable while the Rust implementation evolves.
