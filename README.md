# GracefulPatch
Client patch for Zenless Zone Zero (OSCBWin0.2.0)

## Requirements
- Zig 0.17.0: [Linux](https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz)/[Windows](https://ziglang.org/download/0.17.0/zig-x86_64-windows-0.17.0.zip)

## Building from sources
First, make sure you have zig compiler of the required version available:
```sh
$ zig version
0.17.0
```

If the output matches, simply run
```sh
zig build
```

## Setup
Copy `grace.dll` and `grace.exe` from `zig-out/bin` to the game directory.

If you would like to change the addresses client is redirected to, see the `src/config` directory. After making changes, it is necessary to recompile the patch.

To connect to the server, you have to launch the `grace.exe` executable, not the original `ZZZ.exe`.

## Contributing
[Donate](https://boosty.to/xeondev/donate).

[Join project-specific discord server](https://graceful.xeondev.com).

[Join ReversedRooms discord server](https://discord.xeondev.com).

[Join ReversedRooms telegram channel](https://t.me/reversedrooms).
