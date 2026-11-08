# JavaFX Hotspot

Install JavaFX once, then compile and run small JavaFX programs from PowerShell,
Command Prompt, Windows Terminal, VS Code, Zed, or another IDE terminal:

```powershell
javafxc MyApp.java Helper.java
javafx MyApp
```

`javafxc` compiles into `build\classes` in the current directory. `javafx`
accepts either a simple class name or a fully qualified class name. For a
packaged class, it finds the source file and reads its `package` declaration.

## Requirements

- Windows 10/11, x64
- A JDK with both `java` and `javac` available on `PATH`
- An internet connection for the initial JavaFX SDK download

The installer checks that `java` and `javac` use the same JDK version, checks
the JDK architecture, selects a compatible JavaFX release, and verifies the
SDK's SHA-256 checksum against the checksum published by Gluon.

JavaFX versions and their minimum JDK versions are maintained in
[`javafx-versions.json`](javafx-versions.json). JavaFX SDKs are downloaded only
from `download2.gluonhq.com`.

## Install

Download or clone this repository, open PowerShell in its folder, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer places the SDK and commands under:

```text
%LOCALAPPDATA%\JavaFXHotspot\
```

It adds the command directory to your **user** PATH and configures
`PATH_TO_FX`. Open a new terminal after installation so Windows and your IDEs
pick up the changes. No administrator access, Maven, or changes to the JDK
installation are needed.

## Use

Open a terminal in a Java project directory:

```powershell
javafxc MyApp.java
javafx MyApp
```

The commands search the current project for a uniquely named source file.
If there are duplicate class names, pass a source path to `javafxc` or a fully
qualified class name to `javafx`:

```powershell
javafxc .\src\main\java\example\MyApp.java
javafx example.MyApp
```

Pass application arguments after the class name:

```powershell
javafx MyApp --demo
```

The classpath and JavaFX module path are set for you. Compile related source
files together by listing them after the first source. Projects
with third-party libraries, a custom module descriptor, or IDE-specific build
needs may still require their own project configuration.

## JDK compatibility

The installer uses the active `java` and `javac` commands. It stops with a
clear error if no JDK is found, the tools are from different JDK versions, the
architecture is unsupported, or the JDK is older than the compatibility table.
It does not silently install or switch JDKs.

If you change JDK versions later, run the installer again to select the
matching JavaFX SDK.

## Uninstall

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

The uninstaller removes JavaFX Hotspot's own install folder and its entries
from the current user's PATH and `PATH_TO_FX`. It does not remove Java or
project files.

## Security

The installer downloads a version-pinned SDK and its SHA-256 checksum from
Gluon's HTTPS download host. Review `install.ps1` before running it. Do not pipe
an unreviewed remote script directly into PowerShell.

## Development checks

Run the dependency-free compatibility-table test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-version-mapping.ps1
```
