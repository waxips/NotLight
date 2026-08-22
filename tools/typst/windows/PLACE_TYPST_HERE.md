# Typst Windows runtime

Extract the official `typst-x86_64-pc-windows-msvc.zip` for the pinned version
**0.15.1** somewhere below this directory. Keeping the archive's top-level
folder is supported; NotLight performs a bounded recursive lookup for
`typst.exe`.

Do not replace the pinned release with an arbitrary version. Run
`tools/check_formula_runtime_windows.ps1` after installing both Typst and the
MiTeX local package.
