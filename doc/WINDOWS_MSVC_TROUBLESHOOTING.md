# Windows MSVC Build Troubleshooting

This note records common Windows/Qt/MSVC build failures seen while building Engauge Digitizer, and the shortest known fix.

## Quick MSVC build checklist

Run these from **x64 Native Tools Command Prompt for VS 2022**.

```bat
set PATH=C:\Qt\6.11.0\msvc2022_64\bin;%PATH%
set FFTW_HOME=C:\vcpkg\installed\x64-windows
cd /d D:\Working_Temp\engauge-digitizer-clean
del .qmake.stash
del Makefile Makefile.Debug Makefile.Release
qmake engauge.pro
nmake
```

After the build succeeds, package the portable app:

```bat
dev\windows\package_portable_msvc2022.bat
```

Expected output files:

```text
bin\Engauge.exe
dist\Engauge\Engauge.exe
dist\Engauge-portable.zip
```

## Required files checklist

Before building:

```bat
where qmake
where cl
dir engauge.pro
dir C:\vcpkg\installed\x64-windows\include\fftw3.h
dir C:\vcpkg\installed\x64-windows\lib\fftw3.lib
dir C:\vcpkg\installed\x64-windows\bin\fftw3.dll
```

For a Qt 6.11 MSVC install, these should exist:

```text
C:\Qt\6.11.0\msvc2022_64\bin\qmake.exe
C:\Qt\6.11.0\msvc2022_64\bin\qhelpgenerator.exe
C:\Qt\6.11.0\msvc2022_64\bin\lrelease.exe
C:\Qt\6.11.0\msvc2022_64\plugins\platforms\qwindows.dll
C:\Qt\6.11.0\msvc2022_64\plugins\sqldrivers\qsqlite.dll
```

After building:

```bat
dir bin\Engauge.exe
```

After packaging:

```bat
dir dist\Engauge\Engauge.exe
dir dist\Engauge\fftw3.dll
dir dist\Engauge\platforms\qwindows.dll
dir dist\Engauge\sqldrivers\qsqlite.dll
dir dist\Engauge\documentation\engauge.qch
dir dist\Engauge\documentation\engauge.qhc
dir dist\Engauge-portable.zip
```

## `fatal error C1083: Cannot open include file: 'log4cpp/Category.hh'`

Observed command:

```bat
nmake /f Makefile.Release
```

Observed error:

```text
src\Logger\Logger.h(10): fatal error C1083: Cannot open include file: 'log4cpp/Category.hh': No such file or directory
```

### Cause

The generated Makefile is using the normal log4cpp dependency, but the MSVC build environment does not have log4cpp headers and libraries installed. FFTW may already be available from vcpkg, but that does not provide `log4cpp/Category.hh`.

Engauge includes a local `log4cpp_null` implementation for builds that do not need external log4cpp logging.

### Fix

Regenerate qmake files with `CONFIG+=log4cpp_null`, then rebuild:

```bat
cd /d D:\Working_Temp\engauge-digitizer-clean
qmake6 "CONFIG+=log4cpp_null" engauge.pro
nmake /f Makefile.Release
```

Equivalent with `qmake.exe`:

```bat
C:\Qt\6.11.0\msvc2022_64\bin\qmake.exe "CONFIG+=log4cpp_null" engauge.pro
nmake /f Makefile.Release
```

Expected qmake messages include:

```text
Project MESSAGE: log4cpp_null build: yes
```

After this, the compile line should include:

```text
-Isrc\log4cpp_null\include
```

## `Project ERROR: msvc-version.conf loaded but QMAKE_MSC_VER isn't set`

Observed command:

```bat
cd /d D:\Working_Temp\engauge-digitizer-clean
set PATH=C:\Qt\6.11.0\msvc2022_64\bin;%PATH%
qmake engauge.pro
```

Observed error:

```text
Project ERROR: msvc-version.conf loaded but QMAKE_MSC_VER isn't set
```

### Cause

The repository-local qmake cache, especially `.qmake.stash`, was generated with the wrong compiler environment.

For a correct Qt MSVC build, `.qmake.stash` should contain MSVC values like:

```text
QMAKE_CXX.QMAKE_MSC_VER = 1942
QMAKE_CXX.QMAKE_MSC_FULL_VER = 194234444
```

In the failing `engauge-digitizer-clean` case, `.qmake.stash` had Clang/GCC-style values instead:

```text
QMAKE_CXX.QMAKE_CLANG_MAJOR_VERSION = 17
QMAKE_CXX.QMAKE_GCC_MAJOR_VERSION = 4
```

This can happen when qmake is run from an Intel oneAPI or otherwise mixed compiler prompt. Qt is still using the `win32-msvc` mkspec, but the cached compiler macros do not include `QMAKE_MSC_VER`, so `msvc-version.conf` stops with the error above.

### Fix

Open **x64 Native Tools Command Prompt for VS 2022**, then run:

```bat
set PATH=C:\Qt\6.11.0\msvc2022_64\bin;%PATH%
cd /d D:\Working_Temp\engauge-digitizer-clean
del .qmake.stash
del Makefile Makefile.Debug Makefile.Release
qmake engauge.pro
nmake
```

If `qmake` is not found, use the full path:

```bat
C:\Qt\6.11.0\msvc2022_64\bin\qmake.exe engauge.pro
```

### Verify the compiler prompt

Before running qmake, check:

```bat
where cl
```

The first result should be Visual Studio MSVC, for example:

```text
C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\...\bin\Hostx64\x64\cl.exe
```

If the first `cl.exe` comes from Intel oneAPI, LLVM, or another toolchain, open a clean Visual Studio x64 Native Tools prompt and rerun the fix above.

## General clean qmake rebuild

When switching Qt versions, compiler prompts, or source directories, regenerate qmake files:

```bat
cd /d D:\Working_Temp\engauge-digitizer-clean
del .qmake.stash
del Makefile Makefile.Debug Makefile.Release
qmake engauge.pro
nmake
```

Use `nmake clean` only after qmake has successfully generated Makefiles.

## FFTW setup for MSVC

Engauge uses FFTW. On Windows/MSVC, install the x64 FFTW package with vcpkg:

```bat
cd /d C:\
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
bootstrap-vcpkg.bat
vcpkg integrate install
vcpkg install fftw3:x64-windows
```

If vcpkg is already installed, only this is usually needed:

```bat
cd /d C:\vcpkg
vcpkg install fftw3:x64-windows
```

The expected runtime DLL path is:

```text
C:\vcpkg\installed\x64-windows\bin\fftw3.dll
```

The portable packaging script checks this path automatically:

```bat
dev\windows\package_portable_msvc2022.bat
```

Alternatively, set `FFTW_HOME` if FFTW is installed somewhere else:

```bat
set FFTW_HOME=C:\path\to\fftw
```

Then the script expects:

```text
%FFTW_HOME%\bin\fftw3.dll
```

## `windeployqt` cannot query `qtpaths`

Observed command:

```bat
C:\Qt\6.11.0\msvc2022_64\bin\windeployqt.exe .\bin\Engauge.exe
```

Observed error:

```text
Unable to query qtpaths: Error running binary qtpaths: pipe: The system cannot find the file specified.
```

### Cause

`qtpaths.exe` exists and can run directly, but this Qt `windeployqt` invocation fails while trying to launch/query it. Passing `--qtpaths` may still fail with the same message.

### Fix

Use the repository's portable packaging script instead of calling `windeployqt` directly:

```bat
dev\windows\package_portable_msvc2022.bat
```

The script copies the required Qt runtime DLLs and plugins manually, including:

```text
Qt6Core.dll
Qt6Gui.dll
Qt6Help.dll
Qt6PrintSupport.dll
Qt6Sql.dll
Qt6Svg.dll
Qt6Widgets.dll
Qt6Xml.dll
platforms\qwindows.dll
sqldrivers\qsqlite.dll
imageformats\*.dll
```

Expected output:

```text
dist\Engauge\Engauge.exe
dist\Engauge-portable-Le-Xuan-Thang.zip
```

If build or packaging fails with missing `fftw3.h`, `fftw3.lib`, or `fftw3.dll`, verify:

```bat
where cl
dir C:\vcpkg\installed\x64-windows\include\fftw3.h
dir C:\vcpkg\installed\x64-windows\lib\fftw3.lib
dir C:\vcpkg\installed\x64-windows\bin\fftw3.dll
```

### Common `FFTW_HOME` mistake

Wrong:

```bat
set FFTW_HOME=C:\vcpkg\installed\x64-windows\bin\
%FFTW_HOME%
```

The second line tries to run the folder path as a command, which gives:

```text
'C:\vcpkg\installed\x64-windows\bin\' is not recognized as an internal or external command
```

Correct:

```bat
set FFTW_HOME=C:\vcpkg\installed\x64-windows
echo %FFTW_HOME%
dir %FFTW_HOME%\bin\fftw3.dll
```

`FFTW_HOME` should point to the package root, not to `bin`, because the packaging script checks:

```text
%FFTW_HOME%\bin\fftw3.dll
```
