# Put qpdf here

Download the official `qpdf-12.4.0-msvc64.zip` release artifact and extract it
inside this directory. It is okay to preserve the archive's top-level folder.
NotLight searches for `qpdf.exe` below this directory to a bounded depth.

Expected pinned archive SHA-256:

`5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72`

Do not delete the DLLs or license files that ship with the official runtime.

After extraction you can verify the runtime from PowerShell:

```powershell
.\tools\check_qpdf_windows.ps1
```

To verify the downloaded ZIP before deleting it:

```powershell
.\tools\check_qpdf_windows.ps1 -ArchivePath "C:\path\to\qpdf-12.4.0-msvc64.zip"
```
