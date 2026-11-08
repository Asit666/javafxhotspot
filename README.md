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

Open PowerShell, Command Prompt, Windows Terminal, or your IDE's terminal in
your project folder. This is the folder where JavaFX Hotspot will put the
compiled files in `build\classes`.

### Compile your code

```powershell
javafxc MyApp.java
```

- `javafxc` is the JavaFX Hotspot compile command.
- `MyApp.java` is the source file to compile. It can be in the current folder
  or a subfolder.
- The command invokes `javac`, supplies the installed JavaFX SDK, and writes
  `.class` files into `build\classes`.
- Run the compile command again whenever you change your source.

If your app uses helper classes in other source files, list those files too:

```powershell
javafxc MyApp.java Helper.java
```

You can provide a relative path instead of relying on the source-file search:

```powershell
javafxc .\src\main\java\example\MyApp.java .\src\main\java\example\Helper.java
```

The search looks for a uniquely named `.java` file under the current project
folder and ignores generated `build`, `target`, and `.git` folders. If it finds
duplicate filenames, give the source path explicitly.

### Run your program

```powershell
javafx MyApp
```

- `javafx` is the JavaFX Hotspot run command.
- `MyApp` is the class containing `public static void main(String[] args)`.
- The command invokes `java`, adds the installed JavaFX modules, and loads
  compiled classes from `build\classes`.
- Run it from the same project folder where you ran `javafxc`.

For a class declared in a package, Java's full class name includes the package.
For example, `package example;` plus `class MyApp` has the full name
`example.MyApp`. If the source file is found, `javafx MyApp` reads its package
declaration for you. You can also spell out the full name yourself:

```powershell
javafx example.MyApp
```

For the Liquid Glass demo in this repository, run these from the project root:

```powershell
javafxc .\src\main\java\com\example\liquidglass\LiquidGlassDemo.java
javafx com.example.liquidglass.LiquidGlassDemo
```

### Set Java memory

Options such as `-Xmx` and `-Xms` are JVM options, so put them **before** the
class name:

```powershell
javafx -Xmx512m MyApp
javafx -Xms128m -Xmx1g MyApp
```

| Option | Meaning | Example |
|---|---|---|
| `-Xms128m` | Start the Java heap at 128 MB. This is optional. | `javafx -Xms128m MyApp` |
| `-Xmx512m` | Limit the Java heap to 512 MB. This is optional. | `javafx -Xmx512m MyApp` |

Use `k`, `m`, or `g` for kilobytes, megabytes, or gigabytes. Without these
options, Java selects its own heap defaults. `-Xmx` limits only Java heap—not
the whole process, JavaFX native memory, or graphics memory. A limit that is
too small can cause `OutOfMemoryError`.

### Pass arguments to your app

Application arguments go **after** the class name:

```powershell
javafx MyApp --demo
```

If an application argument looks like a JavaFX Hotspot/JVM option, put `--`
before the application's arguments to make the separation explicit:

```powershell
javafx -Xmx512m MyApp -- -Xmx-is-an-app-argument
```

In this example, `-Xmx512m` sets the JVM heap; the text after `--` is passed to
`MyApp` as an application argument.

JavaFX Hotspot sets up the JavaFX module path and compiled-class path for these
commands. It is a lightweight helper, not a full build tool: projects that use
third-party libraries, annotation processors, a custom module descriptor, or
more complex build steps may need Maven, Gradle, or their own IDE configuration.

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
