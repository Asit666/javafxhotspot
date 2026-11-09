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

First download or clone this repository. Then run the installer **from the
folder that contains `install.ps1`**. The path `.\install.ps1` is relative to
PowerShell's current folder; for example, it will fail from `C:\Windows\System32`
because the installer is not there.

### If Git is installed

Clone the project and run the installer:

```powershell
git clone https://github.com/Asit666/javafxhotspot.git "$HOME\javafxhotspot"
Set-Location "$HOME\javafxhotspot"
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

### If Git is not installed

You do not need to install Git. Download and extract the ZIP using PowerShell:

```powershell
$zip = Join-Path $HOME 'javafxhotspot.zip'
$folder = Join-Path $HOME 'javafxhotspot-download'
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://github.com/Asit666/javafxhotspot/archive/refs/heads/main.zip' `
  -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force
Set-Location (Join-Path $folder 'javafxhotspot-main')
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Or, in a browser, open the repository on GitHub, choose **Code → Download ZIP**,
extract the ZIP, then open PowerShell in the extracted `javafxhotspot-main`
folder (the folder containing `install.ps1`) and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Do not run the installer from `C:\Windows\System32` or another folder that
does not contain `install.ps1`. If PowerShell says the script does not exist,
first use `Set-Location` to move to the extracted repository folder.

The installer places the SDK and commands under:

```text
$env:LOCALAPPDATA\JavaFXHotspot\
```

It adds the command directory to your **user** PATH and configures
`PATH_TO_FX`. Open a new terminal after installation so Windows and your IDEs
pick up the changes. No administrator access, Maven, or changes to the JDK
installation are needed.

## Use

Open PowerShell, Command Prompt, Windows Terminal, or your IDE's terminal in
your project folder. This is the folder where JavaFX Hotspot will put the
compiled files in `build\classes`.

### Configure IDE JavaFX imports

After installing JavaFX Hotspot, open a terminal in your Java project and run:

```powershell
javafxsetup
```

By default, this configures JavaFX for the common Java IDEs:

- **VS Code:** adds JavaFX JARs to `.vscode\settings.json`.
- **Eclipse:** creates or updates `.project` and `.classpath`.
- **IntelliJ IDEA:** creates or updates `.idea` library/module configuration.
- **Apache NetBeans:** updates JavaFX compile/runtime settings in an existing
  Ant project (`nbproject\project.properties`).
- **Zed:** creates or updates Eclipse Java project metadata, which Zed's Java
  extension (JDTLS) uses to resolve the project classpath.
- **Google Antigravity:** writes the shared VS Code-compatible
  `.vscode\settings.json` Java library configuration.

Existing unrelated project settings and library references are preserved.
The SDK paths are local to the current computer; run `javafxsetup` on each
computer after installing JavaFX Hotspot. Run the command from a new terminal
after installation; restart the IDE if it was open during installation.

To configure one IDE only, or detect project formats already present, use:

```powershell
javafxsetup -IDE vscode
javafxsetup -IDE eclipse
javafxsetup -IDE intellij
javafxsetup -IDE netbeans
javafxsetup -IDE zed
javafxsetup -IDE antigravity
javafxsetup -IDE auto
```

For Zed, install its Java extension and open the project root after running
`javafxsetup`. The extension uses Eclipse JDT Language Server (JDTLS); the
generated `.project` and `.classpath` files provide the JavaFX project
classpath. For Google Antigravity, install/enable its Java language support
and open the configured project folder; it uses the workspace Java library
settings written for VS Code compatibility.

The command configures classpaths so the IDE can resolve `import javafx...`.
JavaFX applications may also need JavaFX VM options in an IDE's run
configuration; `javafxc` and `javafx` provide ready-to-use compile/run commands
in any IDE terminal.

If `javafxsetup` is not recognized, the installed commands are from an older
version. Download the latest repository ZIP and rerun `install.ps1`; the
installer updates the commands without downloading JavaFX again when the
compatible SDK is already installed.

The commands use `.cmd` launchers to run their internal PowerShell scripts
with `-ExecutionPolicy Bypass`, so you do not need to change your machine's
PowerShell execution policy. Open a new terminal after reinstalling so it
finds the updated launchers.

### Compile your code

```powershell
javafxc MyApp.java
```

- `javafxc` is the JavaFX Hotspot compile command.
- `MyApp.java` is the source file to compile. It can be in the current folder
  or a subfolder.
- The command invokes `javac`, supplies the installed JavaFX SDK, and writes
  `.class` files into `build\classes`.
- It also copies resource files from `src\main\resources` or `resources` into
  `build\classes`, preserving their subfolders.
- Run the compile command again whenever you change your source.

If your app uses helper classes in other source files, list those files too:

```powershell
javafxc MyApp.java Helper.java
```

You can provide a relative path instead of relying on the source-file search:

```powershell
javafxc .\src\main\java\example\MyApp.java .\src\main\java\example\Helper.java
```

For an FXML app, put FXML, CSS, images, and other resources under
`src\main\resources`. For example:

```text
src\main\java\example\MyApp.java
src\main\resources\example\Main.fxml
src\main\resources\example\app.css
```

After compiling, those files are available on the classpath. Load them using
classpath-relative URLs:

```java
FXMLLoader loader = new FXMLLoader(MyApp.class.getResource("/example/Main.fxml"));
Parent root = loader.load();
scene.getStylesheets().add(
    MyApp.class.getResource("/example/app.css").toExternalForm());
```

FXML code needs the JavaFX FXML module. JavaFX Hotspot adds JavaFX modules
automatically, and `javafxc` copies the resources when it compiles your source.

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

The demo loads its layout from
`src\main\resources\com\example\liquidglass\liquid-glass.fxml` and its styles
from `liquid-glass.css` in the same folder. The FXML defines the visible title
and caption, while the Java code creates the animated-looking background and
glass effect. The default `javafx.controls,javafx.fxml` modules are sufficient
for this demo.

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
commands. By default it enables `javafx.controls` and `javafx.fxml`. If your
app uses other JavaFX modules, set `JAVAFX_MODULES` to a comma-separated list
in the terminal before compiling and running. For example:

```powershell
$env:JAVAFX_MODULES = "javafx.controls,javafx.fxml,javafx.media"
javafxc MyApp.java
javafx MyApp
```

Use module names such as `javafx.media`, `javafx.web`, or `javafx.swing` only
when the app needs them. This avoids resolving unused JavaFX modules by
default; it reduces unnecessary module resolution, but does not guarantee a
specific total RAM reduction because JavaFX also uses native and graphics
memory. JavaFX Hotspot is a lightweight helper, not a full build tool:
projects that use third-party libraries, annotation processors, a custom
module descriptor, or more complex build steps may need Maven, Gradle, or their
own IDE configuration.

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
Set-Location "$HOME\javafxhotspot-download\javafxhotspot-main"
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

If you extracted the repository somewhere else, use `Set-Location` with that
folder instead. The command must be run from the folder containing
`uninstall.ps1`. To print the install directory in PowerShell, use:

```powershell
Join-Path $env:LOCALAPPDATA 'JavaFXHotspot'
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
