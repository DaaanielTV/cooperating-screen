# Contributing to Cooperating Screen

Thanks for your interest in contributing.

## Getting Started

1. Fork the repository and create a feature branch.
2. Keep changes focused and minimal.
3. Add or update documentation for behavior/configuration changes.
4. Run relevant checks before submitting.

## Development Checks

- Flutter app:
  - `cd cosc && flutter analyze`
  - `cd cosc && flutter test`
- Signaling server:
  - `cd signaling_server && npm run test` (placeholder script in current scaffold)

## Pull Request Guidelines

- Use clear commit messages.
- Describe what changed and why.
- Include testing notes and any known limitations.
- Avoid committing generated files, caches, logs, or secrets.

## Reporting Issues

When filing issues, include:
- environment details
- reproduction steps
- expected vs actual behavior
- relevant logs/errors
