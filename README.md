# JavaFX Hotspot

Install JavaFX once, then use `javafxc`, `javafx`, `javafxsetup`, and
`javafxupdate` from PowerShell, Command Prompt, Windows Terminal, VS Code, Zed,
or another IDE terminal.

## Requirements

- Windows 10/11, x64
- JDK 11 or newer, with both `java` and `javac` available on `PATH`
- An internet connection for the initial installation and `javafxupdate`

The installer checks that `java` and `javac` use the same JDK version, checks
the JDK architecture, selects a compatible JavaFX release, and verifies the
SDK's SHA-256 checksum against the checksum published by Gluon.

JavaFX versions and their minimum JDK versions are maintained in
[`javafx-versions.json`](javafx-versions.json). JavaFX SDKs are downloaded only
from `download2.gluonhq.com`.

## Install

First download or clone this repository. Run the installer using the full path
to `install.ps1`; no particular PowerShell working directory is required.

### If Git is installed

If you do not already have the repository folder, clone it and run the
installer:

```powershell
$repo = Join-Path $HOME 'javafxhotspot'
if (Test-Path -LiteralPath $repo) {
  throw "The folder '$repo' already exists. Use the existing-clone instructions below, or choose another folder."
}
git clone https://github.com/Asit666/javafxhotspot.git $repo
if ($LASTEXITCODE -ne 0) { throw 'Could not clone JavaFX Hotspot; installation was not started.' }
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1')
if ($LASTEXITCODE -ne 0) { throw 'JavaFX Hotspot installation failed.' }
```

If you already have a Git clone, update it instead of cloning over it:

```powershell
$repo = Join-Path $HOME 'javafxhotspot'
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
  throw "No Git clone was found at '$repo'. Use the ZIP installation instructions instead."
}
git -C $repo pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Could not update the existing clone; installation was not started.' }
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1')
if ($LASTEXITCODE -ne 0) { throw 'JavaFX Hotspot installation failed.' }
```

### If Git is not installed

You do not need to install Git. Download and extract the ZIP using PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
$zip = Join-Path $HOME 'javafxhotspot.zip'
$folder = Join-Path $HOME 'javafxhotspot-download'
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://github.com/Asit666/javafxhotspot/archive/refs/heads/main.zip' `
  -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force
$repo = Join-Path $folder 'javafxhotspot-main'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1')
if ($LASTEXITCODE -ne 0) { throw 'JavaFX Hotspot installation failed.' }
```

For a clean bootstrap or when a previous extraction may be stale, use a new
folder name (for example, `javafxhotspot-bootstrap`) for both `$zip` and
`$folder`. Keep using the exact folder stored in `$repo` in later commands;
downloads and extractions do not create the older `javafxhotspot-download`
folder automatically.

Or, in a browser, open the repository on GitHub, choose **Code → Download ZIP**,
and extract it. Then open PowerShell in the extracted `javafxhotspot-main`
folder (the folder containing `install.ps1`) and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

If you use the relative command `.\install.ps1`, first use `Set-Location` to
move to the extracted repository folder. The full-path commands above also work
from `C:\Windows\System32`.

The installer places the SDK and commands under:

```text
$env:LOCALAPPDATA\JavaFXHotspot\
```

It adds the command directory to your **user** PATH and configures
`PATH_TO_FX`. Open a new terminal after installation so Windows and your IDEs
pick up the changes. No administrator access, Maven, or changes to the JDK
installation are needed.
If you ran the installer from an existing PowerShell window and the command is
still not recognized there, refresh that window's PATH:

```powershell
$env:Path = @(
  [Environment]::GetEnvironmentVariable('Path', 'Machine'),
  [Environment]::GetEnvironmentVariable('Path', 'User')
) -join ';'
```

This is only needed for the already-open terminal; new terminals normally read
the updated user PATH automatically.

## Update

Run this on each Windows laptop where JavaFX Hotspot is installed:

```powershell
javafxupdate
```

`javafxupdate` is installed by the current installer. If PowerShell says the
command is not recognized, first open a new PowerShell window and check
`Get-Command javafxupdate`. If it is still missing (for example, after
uninstalling JavaFX Hotspot), bootstrap again using an existing updated Git
clone as shown above, or install from the latest ZIP below. Do not run `git
clone` into a folder that already exists.

To bootstrap from the latest ZIP, use one folder variable consistently:

```powershell
$ErrorActionPreference = 'Stop'
$zip = Join-Path $HOME 'javafxhotspot-bootstrap.zip'
$folder = Join-Path $HOME 'javafxhotspot-bootstrap'
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://github.com/Asit666/javafxhotspot/archive/refs/heads/main.zip' `
  -OutFile $zip
Expand-Archive -LiteralPath $zip -DestinationPath $folder -Force
$repo = Join-Path $folder 'javafxhotspot-main'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1')
if ($LASTEXITCODE -ne 0) { throw 'JavaFX Hotspot bootstrap installation failed.' }
```

Open a new PowerShell window (or refresh the current window's PATH using the
command above), then verify with `Get-Command javafxupdate` before running it.

The updater downloads the latest published `main` branch archive from this
repository, checks the archive paths and required files, then runs the
installer. It updates the installed commands and selects/installs the JavaFX
SDK compatible with the active JDK. It does not update or replace Java, project
files, or IDEs. An internet connection and a supported JDK are required.
Alternatively, download the latest repository ZIP and run `install.ps1`
manually.

## Use

Open PowerShell, Command Prompt, Windows Terminal, or your IDE's terminal in
your project folder. This is the folder where JavaFX Hotspot will put the
compiled files in `build\classes`.

### Configure IDE JavaFX imports

After installing JavaFX Hotspot, open a terminal in your **application's
project root** (the folder containing `src\main\java`, not the folder where you
extracted JavaFX Hotspot) and run:

```powershell
Set-Location "$HOME\Downloads\src"
javafxsetup -IDE vscode
```

You can also pass the application project folder explicitly from any directory:

```powershell
javafxsetup "$HOME\Downloads\src" -IDE vscode
```

`javafxsetup` prints the folder it configured and warns if that folder does not
look like a Java project. Each IDE option configures only the selected project
folder; running the command in the extracted JavaFX Hotspot folder does not
configure a separate application.

Each selected IDE setup is checked after writing its configuration. Successful
targets are marked `[PASS]`; failed targets show the file or dependency that
could not be read, written, or verified. With `-IDE all`, the command continues
configuring other IDEs after a target fails, then exits with an error summary
that names each failure and its cause.

By default, this configures JavaFX for the common Java IDEs:

- **VS Code:** adds JavaFX JARs to `.vscode\settings.json` and registers
  `src\main\java` as a source folder when present.
- **Eclipse:** creates or updates `.project` and `.classpath`, including a JDK
  container, the detected Java source root (`src\main\java`, `src`, or `java`),
  and `src\main\resources` when present.
- **IntelliJ IDEA:** embeds the JavaFX JARs in the module dependency, repairs
  stale project-local module references, and includes `src\main\resources`
  when present.
- **Apache NetBeans:** updates JavaFX compile/runtime settings in an existing
  Ant project (`nbproject\project.properties`).
- **Zed:** creates or updates Eclipse Java project metadata, which Zed's Java
  extension (JDTLS) uses to resolve the project classpath.
- **Google Antigravity:** writes the shared VS Code-compatible
  `.vscode\settings.json` Java library configuration.

Existing unrelated project settings and library references are preserved.
When updating VS Code settings that use JSONC comments or trailing commas,
`javafxsetup` converts the file to standard JSON and warns that those comments
and trailing commas are removed.
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

Application arguments are passed through as-is, including arguments that look
like JVM options, because JVM memory options are only read before the class name:

```powershell
javafx -Xmx512m MyApp -Xmx-is-an-app-argument
```

Here, `-Xmx512m` sets the JVM heap; `-Xmx-is-an-app-argument` is passed to
`MyApp`.

JavaFX Hotspot sets up the JavaFX module path and compiled-class path for these
commands. By default it enables `javafx.controls` and `javafx.fxml`. If your
app uses other JavaFX modules, set `JAVAFX_MODULES` to a comma-separated list
in the terminal before compiling and running. For example:

```powershell
$env:JAVAFX_MODULES = "javafx.controls,javafx.fxml,javafx.media"
javafxc MyApp.java
javafx MyApp
```

Requested modules are checked against the installed SDK before invoking Java;
typos or modules missing from that SDK are reported directly. Required JavaFX
JARs are also checked for missing or empty files before compilation.

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

The uninstaller is a repository script, not a `javafxuninstall` command.
Download and extract the repository ZIP if it is not already available. In the
same PowerShell window where you bootstrapped or installed from a ZIP, run it
using that extraction's `$repo` folder variable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'uninstall.ps1')
```

For example, if you used a different extraction directory, set `$repo` to that
directory's `javafxhotspot-main` folder first. Do not assume it is
`$HOME\javafxhotspot-download\javafxhotspot-main`; use the actual `$folder`
value you used when downloading.

The uninstaller removes JavaFX Hotspot's own install folder and SDK, duplicate
user PATH entries for its commands, and user `PATH_TO_FX` values pointing
inside its managed SDK. It preserves unrelated user PATH entries and custom
JavaFX SDK paths. It refuses to delete an install folder containing linked
directories, to avoid removing data outside the install folder. It does not
remove Java, machine-wide environment variables, project files, or IDE
configuration files written inside application projects by `javafxsetup`.
It also removes recognized JavaFX Hotspot ZIP downloads and extracted
`javafxhotspot-main` folders from the current user's home directory when they
match the expected repository layout. Git checkouts, linked folders, archives
that cannot be verified, and unrelated files in download folders are preserved
and reported; downloads outside the known names and home directory are not
scanned or removed.
Close and reopen terminals and IDEs after uninstalling. If `javafx` is still
recognized in a new terminal, run `where.exe javafx` to find another copy on
PATH. Each Windows user account must uninstall its own per-user installation.

## Security

The installer downloads a version-pinned SDK and its SHA-256 checksum from
Gluon's HTTPS download host. `javafxupdate` downloads the repository archive
over HTTPS and validates its paths and required files before running the
installer; the repository archive is not separately code-signed. Review
`install.ps1` and the updater before running them. Do not pipe an unreviewed
remote script directly into PowerShell.

## Development checks

Run the Windows PowerShell regression tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-version-mapping.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-ide-setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-update.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-uninstall.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-commands.ps1
```
