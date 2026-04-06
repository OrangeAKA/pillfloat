# Contributing to PillFloat

Thanks for your interest in contributing! PillFloat is a small project and contributions are welcome.

## How to help

- **Bug reports** — Open an issue with steps to reproduce, your macOS version, and what you expected vs what happened.
- **Feature requests** — Open an issue describing what you'd like and why. Discussion before code saves everyone time.
- **Pull requests** — Please open an issue first to discuss the change. This avoids duplicate work and ensures alignment.

## Development setup

```bash
git clone https://github.com/OrangeAKA/pillfloat.git
cd pillfloat
swift build
swift run
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

## Guidelines

- Keep changes small and focused. One fix or feature per PR.
- Test with Wispr Flow running to verify pill detection and repositioning still works.
- No external dependencies. The project uses only Apple system frameworks.

## Code of conduct

Be respectful. That's it.
