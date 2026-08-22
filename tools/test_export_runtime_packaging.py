from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_windows_export_runtime_packaging_contract() -> None:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    preset = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    plugin = (ROOT / "addons/notlight_export/notlight_export_runtime_plugin.gd").read_text(encoding="utf-8")

    assert 'enabled=PackedStringArray("res://addons/notlight_export/plugin.cfg")' in project
    assert 'export_path="dist/NotLightBoard.exe"' in preset
    for excluded in (
        "tools/ffmpeg/windows/bin/*",
        "tools/poppler/windows/Library/bin/*",
        "tools/qpdf/windows/*",
        "tools/typst/windows/*",
        "tools/typst/packages/*",
    ):
        assert excluded in preset

    package_script = (ROOT / "tools/package_export_runtime_windows.ps1").read_text(encoding="utf-8")
    setup_script = ROOT / "tools/setup_windows_dependencies.ps1"
    downloaded_runtime_paths = (
        "tools/ffmpeg/windows/bin/ffmpeg.exe",
        "tools/ffmpeg/windows/bin/ffprobe.exe",
        "tools/poppler/windows/Library/bin/pdfinfo.exe",
        "tools/poppler/windows/Library/bin/pdftoppm.exe",
        "tools/typst/windows/typst.exe",
    )
    committed_runtime_paths = (
        "tools/qpdf/windows/bin/qpdf.exe",
        "tools/qpdf/windows/bin/qpdf30.dll",
        "tools/typst/packages/local/mitex/0.2.7/mitex.wasm",
    )
    for runtime_path in committed_runtime_paths:
        assert (ROOT / runtime_path).is_file(), runtime_path
    for runtime_path in downloaded_runtime_paths:
        if not (ROOT / runtime_path).is_file():
            assert setup_script.is_file(), f"{runtime_path} missing and setup script unavailable"

    assert "package_export_runtime_windows.ps1" in plugin
    assert 'OS.execute("powershell.exe"' in plugin
    for fragment in (
        r"tools\ffmpeg\windows\bin",
        r"tools\poppler\windows\Library\bin",
        r"tools\qpdf\windows\bin",
        r"tools\typst\windows",
        r"tools\typst\packages\local\mitex\0.2.7",
    ):
        assert fragment in package_script

    assert "NOTLIGHT_RUNTIME_MANIFEST.json" in package_script
    assert (ROOT / "tools/check_export_runtime_windows.ps1").is_file()
    assert (ROOT / "tools/fixtures/export_runtime_smoke.pdf").is_file()


def test_desktop_sidecar_resolvers_are_not_windows_only() -> None:
    ffmpeg = (ROOT / "scripts/media/ffmpeg_tools.gd").read_text(encoding="utf-8")
    poppler = (ROOT / "scripts/media/poppler_tools.gd").read_text(encoding="utf-8")
    qpdf = (ROOT / "scripts/media/qpdf_tools.gd").read_text(encoding="utf-8")
    typst = (ROOT / "scripts/media/typst_mitex_tools.gd").read_text(encoding="utf-8")

    assert 'tools/ffmpeg/linux/bin' in ffmpeg
    assert 'tools/ffmpeg/macos/bin' in ffmpeg
    assert 'tools/poppler/linux/bin' in poppler
    assert 'tools/poppler/macos/bin' in poppler
    assert 'tools/qpdf/linux' in qpdf
    assert 'tools/qpdf/macos' in qpdf
    assert 'tools/typst/linux' in typst
    assert 'tools/typst/macos' in typst
    for text in (ffmpeg, poppler, qpdf, typst):
        assert 'OS.has_feature("android")' in text
        assert 'OS.has_feature("ios")' in text


def test_export_plugin_and_storage_cleanup_refuse_link_traversal() -> None:
    plugin = (ROOT / "addons/notlight_export/notlight_export_runtime_plugin.gd").read_text(encoding="utf-8")
    assert 'func _get_name() -> String:' in plugin
    assert 'func _export_end() -> void:' in plugin
    assert 'OS.get_executable_path()' not in plugin  # destination comes from exporter target path
    package_script = (ROOT / "tools/package_export_runtime_windows.ps1").read_text(encoding="utf-8")
    assert 'Assert-NoReparsePoints' in package_script
    assert 'ReparsePoint' in package_script
    assert 'Remove-Item -LiteralPath $Destination -Recurse -Force' in package_script

    for relative in (
        "scripts/assets/asset_blob_store.gd",
        "scripts/data/board_repository.gd",
        "scripts/media/formula_render_service.gd",
    ):
        text = (ROOT / relative).read_text(encoding="utf-8")
        assert "is_link(" in text, relative


def test_poppler_release_bundle_is_pinned_and_minimized() -> None:
    poppler_bin = ROOT / "tools/poppler/windows/Library/bin"
    required = {
        "pdfinfo.exe",
        "pdftoppm.exe",
        "poppler.dll",
        "freetype.dll",
        "zlib.dll",
        "jpeg8.dll",
        "libcurl.dll",
        "libssh2.dll",
        "libcrypto-3-x64.dll",
        "openjp2.dll",
        "lcms2.dll",
        "libpng16.dll",
        "tiff.dll",
        "deflate.dll",
        "Lerc.dll",
        "liblzma.dll",
        "zstd.dll",
    }
    if poppler_bin.is_dir():
        assert {p.name for p in poppler_bin.iterdir() if p.is_file()} == required
    else:
        assert (ROOT / "tools/setup_windows_dependencies.ps1").is_file()

    source_info = (ROOT / "tools/poppler/SOURCE_INFO.md").read_text(encoding="utf-8")
    assert "v26.02.0-0" in source_info
    assert "993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5" in source_info
    assert "refresh_windows_runtime.ps1" in source_info

    refresh = (ROOT / "tools/poppler/refresh_windows_runtime.ps1").read_text(encoding="utf-8")
    assert "Get-FileHash -Algorithm SHA256" in refresh
    assert "993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5" in refresh
    for name in required:
        assert f'"{name}"' in refresh

    dependency_notices = ROOT / "THIRD_PARTY_LICENSES/Poppler-Windows-Dependencies"
    assert (dependency_notices / "README.md").is_file()
    assert (dependency_notices / "FreeType-FTL.txt").is_file()
    assert (dependency_notices / "libjpeg-turbo-IJG.txt").is_file()
    assert (dependency_notices / "OpenSSL-Apache-2.0.txt").is_file()
    assert (ROOT / "THIRD_PARTY_LICENSES/Poppler-Data-GPL-3.0.txt").is_file()
    runtime_gpl3 = ROOT / "tools/poppler/windows/share/poppler/COPYING.gpl3"
    if poppler_bin.is_dir():
        assert runtime_gpl3.is_file()
