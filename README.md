# JavaFX Hotspot

Install JavaFX once, then use `javafxc` and `javafx` from PowerShell, Command
Prompt, Windows Terminal, VS Code, Zed, or another IDE terminal.

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

Open a terminal in your Java project directory (the folder where you want
`build\classes` created), then compile and run:

```powershell
javafxc MyApp.java
javafx MyApp
```

`javafxc` compiles `.java` source files into `build\classes` in the current
directory. `javafx` launches the compiled class from there. Compile again
after changing source code. Each project directory gets its own
`build\classes` output.

The commands search the current project and its subfolders for a uniquely
named source file, so a source in `src\main\java` can be found by its short
filename. You can also give an explicit source path. If your app uses a
package, `javafx` reads the source's package declaration when resolving a
short class name:

```powershell
javafxc .\src\main\java\example\MyApp.java .\src\main\java\example\Helper.java
javafx MyApp
```

If more than one source file has the same name, give `javafxc` the path to the
one you want. If class-name lookup is ambiguous, give `javafx` the full package
and class name:

```powershell
javafxc .\src\main\java\example\MyApp.java
javafx example.MyApp
```

Pass application arguments after the class name. Use `--` to mark the end of
JavaFX Hotspot options:

```powershell
javafx MyApp -- --demo
```

JVM memory options go **before** the class name. For example, set the maximum
Java heap to 512 MB:

```powershell
javafx -Xmx512m MyApp
javafx -Xms128m -Xmx1g MyApp --demo
```

`-Xmx` is optional; without it, Java chooses a default based on the machine. It
limits only Java heap memory, not all process memory (for example, JavaFX and
graphics resources). Setting it too low can cause `OutOfMemoryError`.

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
