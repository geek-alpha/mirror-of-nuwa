# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4.7 project (`VR_World`) targeting mobile VR. The repository root is the Godot project root; `project.godot` holds engine settings (Jolt Physics, Mobile renderer) and is best edited from the editor UI. Use the following layout as features are added:

- `scenes/` — reusable scenes (`.tscn`), one per UI or world object.
- `scripts/` — GDScript sources (`.gd`), organized by feature or node type.
- `assets/` — imported art, audio, and textures.
- `tests/` — test scripts.
- `.godot/` — generated cache; never commit (already gitignored).

## Build, Test, and Development Commands

Godot is the build tool; there is no package manager or CI yet.

- `godot --path . -e` — open the project in the editor.
- `godot --path .` — run the project locally.
- `godot --path . --headless --import` — import assets and validate resources without a window.
- `godot --path . --headless -s tests/run_tests.gd` — run tests (once GdUnit4 is installed).

## Coding Style & Naming Conventions

- Indent GDScript with tabs and follow the official Godot GDScript style guide.
- Use `snake_case` for variables, functions, and script files; `PascalCase` for class and scene names; `SCREAMING_SNAKE_CASE` for constants.
- Keep `.editorconfig` current (UTF-8) and format code before committing. No linter is configured yet; consider `gdlint` once scripts exist.

## Testing Guidelines

No tests exist yet. When added, use GdUnit4. Place test scripts in `tests/`, named `test_<feature>.gd`, with methods `test_<behavior>()`. Run them with the headless command above; cover new game logic as it is written.

## Commit & Pull Request Guidelines

The repository has no Git history yet, so adopt Conventional Commits from the first commit: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`. PRs must include a short description of the change, reference the linked issue (e.g. `Closes #12`), include screenshots for visual changes, and be rebased on the latest main.

## Agent-Specific Instructions

- Never modify files under `.godot/` or `android/`.
- Preserve `.editorconfig`, `.gitignore`, and `.gitattributes`.
- Prefer making scene and script changes through the Godot editor where possible; hand-edit only with care.
