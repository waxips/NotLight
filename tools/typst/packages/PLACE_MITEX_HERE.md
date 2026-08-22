# MiTeX local package

Do not manually invent the package layout. Download the official Typst Universe
archive `mitex-0.2.7.tar.gz`, then from the project root run:

```powershell
.\tools\prepare_mitex_windows.ps1 -ArchivePath "C:\path\to\mitex-0.2.7.tar.gz"
```

The helper validates the archive paths, package manifest, license, required
WASM/Typst files, size bounds and absence of remote Typst package imports before
installing it into:

`tools/typst/packages/local/mitex/0.2.7/`

The generated `.NOTLIGHT_MITEX_PACKAGE_INFO.json` records the source archive
SHA-256 and a deterministic digest of the installed package contents. The
archive itself does not need to stay inside the NotLight project.
