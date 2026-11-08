## Project dependency and CLI installation

- Before installing anything, inspect the repository's instructions, manifests, lockfiles, and existing environment. Follow its documented setup and package manager; do not switch managers or create a competing lockfile.
- Keep project dependencies in a project-local or explicitly managed environment. For Python, use the project's virtual environment (commonly `.venv`) or documented manager such as `uv`; never install project packages into system or user Python with bare `pip install`.
- For JavaScript and TypeScript, use the package manager indicated by the project lockfile and its local scripts/dependencies. This includes npm, pnpm, and Bun. Do not use global install options such as `npm install -g`, `pnpm add -g`, or `bun add -g` for project tools.
- If a required CLI is absent, prefer a project-local development dependency or a one-off package-manager invocation (`npx --yes`, `pnpm dlx`, or `bunx`, chosen to match the project). Check the project's documented version and package source before invoking it.
- Treat commands that add or upgrade dependencies as project changes: preserve the lockfile, use the existing package manager, and review the resulting diff. Do not run dependency installation when inspection or existing tooling is sufficient.
- Avoid system-wide or user-wide installs and elevated install commands. If the project has no documented isolated setup and a global change seems necessary, explain the need and ask first.
