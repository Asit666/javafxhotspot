# Java Package Manager — Prototype Proposal

> **Status:** Concept only. This document proposes a future general-purpose
> Java project tool. It does not change JavaFX Hotspot's current scope, which
> remains JavaFX SDK setup and the `javafxc` / `javafx` commands. No package
> manager is implemented by this proposal.

## 1. Purpose

Explore a beginner-friendly, Cargo-inspired command-line workflow for Java
projects. A user should be able to create a project, add libraries, build, run,
test, and update it without first learning Maven or Gradle command syntax.

The tool should make Java easier to start with while using established Java
formats and dependency infrastructure. It should not create a new public
package registry or replace Maven Central.

## 2. Goals

- Offer one approachable command (`jpm`, a working name) across Windows,
  macOS, and Linux.
- Create and operate on ordinary Java projects that work with established
  IDEs and build tools.
- Manage Java dependencies from Maven Central, including transitive
  dependencies and version conflicts.
- Detect the selected JDK and provide actionable compatibility errors.
- Keep project dependencies reproducible and reviewable.
- Install and update the CLI without administrator access when possible.
- Keep JavaFX optional: it is one supported library/toolkit, not a requirement
  of the general Java package manager.

## 3. Non-goals

- Reimplementing Maven Central, Maven Resolver, or the Java compiler.
- Installing or silently switching a user's JDK by default.
- Publishing arbitrary packages to a new registry.
- Guaranteeing that every third-party library, plugin, IDE, or operating
  system configuration works without project-specific setup.
- Changing the existing JavaFX Hotspot installer as part of this prototype.

## 4. Example user experience

The following examples describe the intended experience, not implemented
commands:

```text
jpm new hello
cd hello
jpm run
jpm add org.apache.commons:commons-lang3:3.18.0
jpm test
jpm build
jpm update
```

Possible supporting commands:

```text
jpm init
jpm remove org.apache.commons:commons-lang3
jpm tree
jpm java list
jpm doctor
jpm clean
```

Names and exact syntax should be tested with Java beginners before the CLI is
committed to a public interface. In particular, `jpm` is a placeholder until
command-name availability and possible conflicts have been checked.

## 5. Proposed project model

### Standard build files are the source of truth

The initial implementation should create a conventional Maven project with a
`pom.xml`, standard `src/main/java` and `src/test/java` folders, and the Maven
Wrapper (`mvnw` / `mvnw.cmd`). Dependencies, compiler settings, plugins, and
repositories remain represented in the POM rather than in a second,
competing manifest.

The CLI can provide simpler commands while delegating established build and
dependency behavior to the Maven Wrapper. Maven is downloaded on first use
through its wrapper and cached in the user's normal Maven cache; a system-wide
Maven installation is not required.

The generated project remains editable in IntelliJ IDEA, Eclipse, NetBeans,
VS Code, and other tools that understand Maven. Users can run Maven directly
when they need an advanced feature:

```text
./mvnw test
mvnw.cmd test
```

### Why not invent a package format first?

A custom manifest, lockfile, resolver, and dependency cache would duplicate
years of ecosystem work and could make projects less interoperable. A
Cargo-like interface does not require inventing Cargo-like internals. First
prove that a friendly front end to standard Java projects solves the
beginner-experience problem.

### Future manifest decision

Only consider a dedicated manifest such as `jpm.toml` after user research
shows a concrete need that a simplified POM workflow cannot meet. Before
adding one, define a single source of truth, lossless mapping rules, migration
behavior, and interoperability expectations. Do not let a custom manifest and
POM silently disagree.

## 6. Dependency behavior

- Use Maven coordinates: `groupId:artifactId:version`.
- Resolve artifacts from Maven Central by default.
- Do not add repositories automatically based on a package name or an
  untrusted user-supplied URL.
- Preserve transitive dependencies and surface version conflicts clearly.
- Record direct dependency changes in the POM and leave a readable diff.
- Never execute dependency-provided build plugins without the project's normal
  build-tool behavior and an explicit, understandable trust boundary.
- `jpm update` should show proposed version changes before applying them.
- An update must not silently upgrade the JDK, JavaFX, or unrelated plugins.

### Reproducibility

Maven POMs declare dependency versions but do not natively provide the same
general-purpose dependency lockfile workflow as Cargo. Before promising
`jpm.lock`, research Maven's dependency-management and locking ecosystem,
including effective POMs, dependency convergence, checksum validation, and
reproducible-build practices.

If a lockfile is introduced later, specify:

- The exact resolved artifact coordinates and checksums it records.
- How platform-specific and optional dependencies are represented.
- How the lockfile is updated and reviewed.
- How existing Maven users can still build the project.
- Whether ordinary Maven commands honor the lock or only `jpm` does.

Do not claim fully reproducible dependency resolution until this contract is
implemented and tested.

## 7. JDK detection and compatibility

The CLI must detect the actual executables it will use, not infer the JDK only
from an environment variable or an installation-directory name.

At minimum, `jpm doctor` should report:

- Resolved paths for `java` and `javac`.
- Runtime and compiler versions.
- Whether `java` and `javac` are from compatible JDK installations.
- Operating system and architecture.
- The project's configured Java release and any detected JavaFX version.
- A specific remediation when tools are missing or inconsistent.

Before build or run, validate that the selected JDK satisfies the project's
declared Java release and the requirements of configured frameworks. A
mismatch should stop with an actionable diagnostic; the tool must not silently
switch JDKs or download a JDK without user consent.

The project-level Java version should be explicit and consistent with
`maven.compiler.release` and any toolchain configuration. The CLI should
respect a project-configured toolchain when present and clearly report the
selected compiler and runtime.

## 8. Proposed command responsibilities

| Command | Prototype behavior |
|---|---|
| `jpm new <name>` | Create a conventional Maven project and wrapper; validate the name and destination. |
| `jpm init` | Add minimal Maven project files to an existing directory without overwriting user files. |
| `jpm add <coordinate>` | Validate a coordinate, query Maven metadata, ask for a version if omitted, then update the POM. |
| `jpm remove <groupId:artifactId>` | Remove only the selected direct dependency and show the diff. |
| `jpm run [-- <args>]` | Run the configured main class through the wrapper; explain how to configure one if ambiguous. |
| `jpm test` | Run project tests and return the underlying build's exit code. |
| `jpm build` | Compile and package using the project's configured Maven lifecycle. |
| `jpm update [coordinate]` | Preview available compatible updates; require confirmation before changing files. |
| `jpm tree` | Show the resolved dependency tree and identify conflicts. |
| `jpm doctor` | Diagnose JDK, wrapper, cache, repository, and JavaFX compatibility setup. |
| `jpm clean` | Delegate to the build tool's clean lifecycle; never delete files outside known build output. |

Commands should preserve the build tool's useful output and exit status rather
than hiding failures behind a success-shaped summary.

## 9. Installation and updates

- Provide a versioned release and documented checksums.
- Offer a reviewed Windows PowerShell installer initially; add macOS and Linux
  installation methods only with platform-specific testing.
- Install per user by default; do not require administrator privileges for
  ordinary command installation.
- Avoid piping unreviewed remote scripts directly into a shell.
- Add only the CLI's own bin directory to the user's PATH.
- Never overwrite unrelated tools or change `JAVA_HOME` without explicit
  consent.
- `jpm self-update` (if added) must verify release checksums and explain what
  will change before replacing the executable.
- Provide an uninstall command that removes only files and environment entries
  owned by the CLI.

JavaFX SDK acquisition remains a separate concern. If future JavaFX support
selects an SDK automatically, it must use a maintained JDK compatibility map,
verify an official checksum, and report the exact JavaFX/JDK pair selected.

## 10. Security and supply-chain requirements

- Use HTTPS for metadata, artifacts, wrapper distributions, and releases.
- Verify published hashes for downloaded distributions and artifacts wherever
  available.
- Treat POM files, Maven plugins, annotation processors, and build scripts as
  executable-project inputs, not harmless data.
- Do not execute arbitrary setup scripts as part of `jpm add`.
- Clearly distinguish package metadata from trusted publisher identity; Maven
  coordinates alone do not prove that a dependency is safe.
- Avoid logging credentials, proxy passwords, or private repository tokens.
- Respect Maven's existing settings and credential configuration without
  printing secrets.
- Document that dependency resolution may execute Maven plugins during a build.
- Maintain a vulnerability-reporting contact and a release/update policy
  before recommending broad public adoption.

## 11. Error handling and user experience

Every error should identify:

1. What operation failed.
2. The relevant file, coordinate, JDK, or repository.
3. Whether project files were changed.
4. A concrete next step.

Examples:

```text
No JDK compiler was found.
Install a JDK, then make sure java and javac are both available on PATH.
No project files were changed.
```

```text
JavaFX 25 requires JDK 23 or newer, but this project selected JDK 21.
Choose a compatible JDK or select a JavaFX release supported by JDK 21.
```

Do not silently choose an arbitrary dependency version, repository, JDK, or
main class when multiple choices are plausible. Ask, list candidates, or stop
with a clear message.

## 12. Phased prototype plan

### Phase 0 — validate the idea

- Ask Java beginners to complete common tasks using Maven and the proposed CLI.
- Check the proposed command name on package indexes, Windows, macOS, and Linux.
- Confirm that a thin Maven Wrapper front end provides the desired simplicity.
- Do not build a custom resolver or registry.

### Phase 1 — Windows MVP

- Implement `jpm new`, `init`, `add`, `remove`, `run`, `test`, `build`, and
  `doctor`.
- Generate standard Maven projects and commit the Maven Wrapper scripts and
  wrapper properties; do not commit a downloaded Maven distribution.
- Handle JDK detection and the project's configured main class.
- Test paths containing spaces, non-ASCII user names, and multiple source
  files.
- Keep JavaFX support optional and use it to exercise the JDK compatibility
  diagnostics.

### Phase 2 — reliability and dependency updates

- Implement update previews, dependency-tree output, checksum/error reporting,
  and safe handling of existing project files.
- Decide on a reproducibility/lockfile contract only after ecosystem research.
- Add Windows CI tests using a supported JDK.

### Phase 3 — cross-platform and IDE workflows

- Add macOS and Linux installers and test native paths, shells, and JDK
  architectures.
- Add optional VS Code, IntelliJ, Eclipse, and Zed integrations without making
  any IDE mandatory.
- Document that IDE launch configurations may still need project-specific
  settings.

### Phase 4 — reassess the project model

- Collect usage and interoperability feedback.
- Decide whether Maven remains the sole project model or whether an additional
  Gradle backend is justified.
- Consider a dedicated manifest only with a migration and interoperability
  design.

## 13. Prototype acceptance criteria

The first usable release should not be called ready until all of these are
true:

- A fresh supported JDK can create, compile, test, run, and package a basic
  project using only documented `jpm` commands.
- A second terminal or IDE can import and build the generated standard Maven
  project without requiring `jpm`.
- `jpm add` updates the POM correctly and reports resolution failures without
  corrupting it.
- The tool detects mismatched `java`/`javac` installations and incompatible
  Java releases before compilation.
- Project paths with spaces work on every supported platform.
- A clean install and uninstall affect only the tool's own files and PATH
  entries.
- CI covers generated-project smoke tests, compatibility checks, and
  installer parsing.
- Security, supported JDK versions, update policy, and known limitations are
  documented.

## 14. Open decisions for later

- Is `jpm` an available, memorable command name on all target platforms?
- Is Maven Wrapper the right initial backend for the intended beginner
  audience, or should the first release use Gradle Wrapper?
- Which JDK LTS releases are officially supported?
- Should `jpm new` create a console application, a JavaFX application, or offer
  both templates?
- What should `jpm run` do when a project has multiple main classes?
- Is a dependency lockfile essential for the target use cases, and can it
  remain interoperable with standard Maven builds?
- Which operating systems and CPU architectures belong in the first public
  release?
- What is the maintenance policy for compatibility metadata, SDK checksums,
  and security advisories?

These decisions are intentionally unresolved in this prototype. The current
JavaFX setup tool should remain focused until a separate implementation task
is requested.
