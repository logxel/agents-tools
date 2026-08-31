---
name: python-skills
description: Build, modernize, review, and test production Python projects using Python 3.14 by default and Python 3.13 only when compatibility requires it. Covers architecture, typing, packaging, tooling, async code, testing, security, and maintainable APIs.
---

# Modern Python Development

Use this skill for Python application, library, service, CLI, automation, and infrastructure work. Optimize for code that is easy to change, statically analyzable, testable, observable, secure, and straightforward to upgrade.

## Runtime policy

- Target Python 3.14 by default. Use the newest stable 3.14 syntax and standard-library capabilities when the project permits them.
- Support Python 3.13 as a secondary runtime only when the deployment environment, consumers, or an explicit project requirement demands it. Keep compatibility decisions in `requires-python`, CI, and documentation.
- Do not add compatibility shims for Python versions below 3.13 unless the user explicitly asks for them.
- Treat prerelease interpreters as CI experiments, not production targets, unless the user explicitly requests prerelease support.
- Check Python's current version-status page when making lifecycle or support claims: https://devguide.python.org/versions/.

When changing an existing project, inspect its declared runtime, lockfile, CI matrix, deployment images, and public compatibility promises before using 3.14-only syntax. Do not silently narrow a library's supported versions.

## First inspect, then design

Before editing:

1. Identify whether the code is an application, reusable library, service, CLI, one-off script, or monorepo package.
2. Read `pyproject.toml`, package layout, test configuration, CI, lockfiles, and the nearest existing tests.
3. Preserve established tools and conventions unless there is a concrete reason to migrate.
4. Find the public boundary: CLI commands, HTTP handlers, exported package symbols, jobs, or integration adapters.
5. Make the smallest coherent change, then run the narrowest relevant checks followed by the full project checks.

Prefer explicit tradeoffs over universal rules. A small private script does not need a publishable package architecture; a public library does.

## Project architecture

- Keep modules cohesive: group code that changes together and give each module one understandable responsibility.
- Prefer shallow, meaningful boundaries over folders named `utils`, `helpers`, or `common` that become dependency dumping grounds.
- For libraries and long-lived services, prefer a `src/<package>/` layout so tests do not accidentally import the checkout instead of the installed distribution. A flat layout is acceptable for a genuinely small application or script.
- Separate domain logic from I/O: keep HTTP, database, filesystem, subprocess, and vendor SDK calls at adapters or edges.
- Make dependencies point inward toward stable domain code. Avoid cycles and avoid having domain code import framework details.
- Use package `__init__.py` files to expose a deliberate public API. Define `__all__` only for meaningful public exports; do not re-export every internal symbol.
- Prefer composition and small protocols over inheritance-heavy frameworks. Use dependency injection at integration boundaries when it makes tests and replacement easier.
- Use `dataclass` for typed value objects and `TypedDict` only when the data must remain mapping-shaped. Do not use untyped dictionaries as an implicit domain model.
- Keep configuration explicit and typed. Load environment or files at the boundary, validate once, and pass an immutable or clearly scoped settings object inward.

For a reusable package, treat import paths and function signatures as contracts. Avoid exposing implementation modules accidentally, and use deprecation paths before removing public behavior.

## Packaging and dependencies

Use the standards-based packaging model documented by PyPA:

- Keep a root `pyproject.toml` with `[build-system]` and, for normal projects, `[project]` metadata.
- Declare `requires-python` to match the supported matrix: normally `>=3.14`; use `>=3.13` only when 3.13 is intentionally supported as well.
- Keep runtime dependencies separate from development dependencies. Use optional dependencies for installable consumer-facing features and standardized `[dependency-groups]` for internal test, lint, docs, and tooling groups when the chosen frontend supports them.
- Choose one build backend and one environment/dependency workflow that fits the repository. Do not introduce a second package manager casually.
- Prefer a lockfile or equivalent reproducible environment record for applications and deployed services. For libraries, keep published dependency ranges compatible and let consumers resolve their environment.
- Build and install the wheel/sdist in CI so packaging errors are caught; tests that pass only from the checkout are insufficient.
- Do not use `python setup.py install`, `develop`, `sdist`, or `bdist_wheel`. Use the project's frontend, or standards-based commands such as `python -m pip install .` and `python -m build` where appropriate.
- Avoid dynamic versioning and metadata when static metadata works. If metadata must be dynamic, declare it explicitly and ensure isolated builds contain every build dependency.
- Do not over-pin library runtime dependencies. Pin or lock applications and development environments according to their reproducibility requirements.

Read the current specifications before changing packaging behavior:

- https://packaging.python.org/en/latest/guides/writing-pyproject-toml/
- https://packaging.python.org/en/latest/specifications/dependency-groups/
- https://packaging.python.org/en/latest/guides/modernize-setup-py-project/

## Type safety

Use typing to make interfaces and refactors safer without turning annotations into ceremony:

- Annotate public function parameters, return values, important attributes, and callbacks. Infer obvious local variables.
- Prefer Python 3.14 syntax: built-in generics (`list[str]`, `dict[str, int]`), `X | None`, and the `type` statement for aliases. When supporting 3.13, verify every syntax and typing feature against that baseline.
- Import collection and callable abstractions from `collections.abc` where appropriate (`Sequence`, `Mapping`, `Iterable`, `Callable`). Use the widest input type the implementation truly accepts and a concrete return type when that is what it returns.
- Prefer `Protocol` for structural interfaces, `Literal` for finite values, `TypeGuard`/type narrowing where useful, and `Self` for fluent APIs. Use generics when they express a real relationship between inputs and outputs.
- Treat `Any` as an escape hatch. Isolate it at an untyped boundary, explain why it is needed, and avoid allowing it to spread through the core.
- Use `object` when a function accepts any object but does not need to inspect a more specific type.
- Avoid type casts that merely silence a checker. Narrow with validation, `isinstance`, a protocol, or a better boundary type.
- For typed libraries, ship inline annotations and a `py.typed` marker when the public interface is type-complete. Type-check the same public surface consumers use.
- Choose one primary checker (for example, basedpyright/pyright or mypy) and configure it in `pyproject.toml`. Keep checker exceptions narrow and explained.
- Use runtime validation libraries only when runtime validation is actually required; static annotations alone do not validate untrusted data.

Use the typing guidance as the source of truth because syntax and best practices evolve: https://typing.python.org/en/latest/reference/best_practices.html and https://typing.python.org/en/latest/guides/libraries.html.

## Formatting, linting, and quality gates

For a new project, a practical default is Ruff for formatting and linting plus a strict-but-incremental type checker. For an existing project, follow its configured tools first.

- Keep formatting deterministic and run it in CI.
- Enable high-value lint rules first: correctness, import hygiene, unused code, exception quality, security-sensitive patterns, and modernization rules compatible with the runtime baseline.
- Do not enable every rule blindly. Resolve conflicts with project intent explicitly and keep per-file exceptions rare.
- Run formatting and linting on changed files locally, then the full source and test tree in CI.
- Keep configuration in `pyproject.toml` unless a tool requires another file. Avoid duplicated tool configuration.
- Treat warnings from the type checker, test runner, deprecations, and resource leaks as actionable; do not blanket-ignore them.

Tool choices are defaults, not a mandate. The durable requirement is one reproducible formatter/linter, one type-checking strategy, and one documented command path for contributors.

## Testing

Use pytest or the repository's existing test framework:

- Test behavior and contracts, not private implementation details.
- Keep unit tests fast and deterministic. Put network, real databases, clocks, subprocesses, and external services behind explicit integration tests or replaceable adapters.
- Use fixtures for shared setup, but keep fixture graphs shallow and visible. Prefer factories for data variation.
- Use parametrization for a matrix of inputs and expected outcomes rather than copy-pasted tests.
- Test failure modes, cancellation, timeouts, malformed input, authorization boundaries, and resource cleanup—not just the happy path.
- Test public package behavior after installing the built artifact, especially for libraries.
- Run the test suite against Python 3.14. If 3.13 is in the support matrix, run it too; do not claim compatibility based on syntax inspection alone.
- Measure coverage as a signal, not a target. Prioritize branches that protect money, data integrity, permissions, retries, and externally visible behavior.
- For property-based or fuzz testing, use it where invariants or input spaces are large; do not add it as decoration.

For pytest configuration and import behavior, consult https://docs.pytest.org/en/stable/explanation/goodpractices.html.

## Async and concurrency

- Choose synchronous or asynchronous execution based on the dominant I/O model and the libraries at the boundary. Do not make a synchronous workload async merely for fashion.
- In async code, never block the event loop with synchronous network, filesystem, subprocess, or CPU-heavy work. Use an async-native dependency or an explicit worker boundary.
- Use `asyncio.TaskGroup` for related child tasks that should share structured lifetime and failure behavior. Preserve cancellation; do not catch `CancelledError` and continue silently.
- Set explicit timeouts around external operations and make retry policy bounded, observable, and safe for the operation's idempotency.
- Close clients, streams, tasks, and async generators deterministically. Ensure startup and shutdown paths are testable.
- Keep sync/async boundaries few and obvious. Do not call `asyncio.run()` from code that may already be inside an event loop.

Use the standard-library asyncio task documentation for current semantics: https://docs.python.org/3/library/asyncio-task.html.

## Errors, APIs, and observability

- Raise specific domain or boundary exceptions with useful context. Preserve the original exception with exception chaining when translating errors.
- Catch exceptions only where the layer can recover, add context, translate the public error, or perform required cleanup. Never use a bare `except` for normal control flow.
- Validate untrusted input at the boundary and return stable, actionable error shapes from public APIs.
- Make retries, idempotency, pagination, timeouts, and partial failure behavior explicit in service APIs.
- Use the standard `logging` machinery or the project's structured logging system. Libraries should not configure global logging or emit unsolicited logs at import time.
- Include operation identifiers and safe context in logs; never log secrets, tokens, credentials, or unredacted sensitive payloads.
- Use metrics/traces for measurable service behavior, not logging as a substitute for every signal.

## Security and reliability

- Treat all external data as untrusted. Validate types, sizes, encodings, paths, URLs, and permissions at the boundary.
- Avoid `eval`, `exec`, unsafe deserialization, shell interpolation, and dynamic imports from untrusted input. Pass subprocess arguments as a list and use an explicit working directory and timeout.
- Use `secrets` for security-sensitive randomness, constant-time comparison for secrets where relevant, and a real secret manager or injected environment for credentials.
- Use parameterized database queries and least-privilege credentials.
- Make file handling resistant to path traversal and symlink surprises when inputs are attacker-controlled.
- Keep dependencies current within the declared compatibility range, review transitive changes, and run dependency/security scans in CI where the repository supports them.
- Make cleanup exception-safe with context managers, `try/finally`, and explicit ownership of resources.

## Performance and portability

- Measure before optimizing. Use profiling or benchmarks that represent the real workload.
- Prefer clear standard-library primitives (`pathlib`, context managers, iterators, `functools`, `collections`) before adding dependencies.
- Avoid accidental quadratic work, unbounded memory growth, repeated parsing, and blocking calls in request paths.
- Be explicit about timezone-aware datetimes, encodings, locale assumptions, and platform-specific paths.
- Do not depend on CPython implementation details unless the project explicitly targets CPython and the tradeoff is documented.

## Modernization workflow

When upgrading an existing project:

1. Record the current runtime and tool matrix, then decide whether 3.14-only code is allowed or whether 3.13 compatibility remains required.
2. Add or correct `requires-python` and CI coverage before changing syntax.
3. Modernize packaging and configuration in a separate, reviewable change when possible.
4. Replace deprecated APIs with supported equivalents, keeping behavior and public imports stable.
5. Improve types at boundaries first, then tighten checker settings incrementally.
6. Add regression tests for each changed behavior, especially around errors and async cancellation.
7. Run formatter, linter, type checker, unit/integration tests, and an artifact install/build check.
8. Document intentional compatibility limits and migration notes.

## Completion checklist

Before handing off Python work, verify the applicable items:

- Runtime baseline is explicit and is 3.14 by default; 3.13 support is tested if claimed.
- Packaging metadata, build backend, dependencies, and development groups are coherent.
- Public boundaries are typed, stable, and free of accidental internal exports.
- Tests cover success, failure, boundary, cleanup, and concurrency behavior relevant to the change.
- Formatter, linter, type checker, and tests pass without unexplained broad suppressions.
- Async code has bounded timeouts, cancellation-safe cleanup, and no blocking event-loop work.
- Input validation, subprocess/database usage, secrets, logging, and dependency changes meet the security bar.
- The built artifact can be installed and used in a clean environment when the project is packageable.
