NOTLIGHT FOR WINDOWS — QUICK START
==================================

QUICK START
1. Extract the ENTIRE ZIP into a normal folder (for example, Documents\NotLight).
2. Double-click START_NOTLIGHT.bat.
3. On the first launch, an Internet connection is required. The starter downloads
   the pinned media/PDF/formula components directly from their upstream providers
   and verifies the downloaded archives before installing them.
4. When setup finishes, NotLight starts automatically.
5. Later, use START_NOTLIGHT.bat again. Already-installed dependencies are reused.

IMPORTANT
- Do not run NotLight directly from inside the ZIP.
- Do not copy only NotLight.exe. Keep the whole extracted folder together.
- The first-run dependency download is intentional. NotLight's public ZIP does not
  redistribute several third-party GPL/LGPL runtime binaries; the setup script gets
  the pinned copies directly from their providers instead.
- NotLight stores your application data locally through Godot's user data directory.

WINDOWS WARNING / SMARTSCREEN
This community build is not code-signed. Windows may therefore show a SmartScreen
warning for a newly downloaded release. Verify that you downloaded NotLight from the
project's official GitHub release or Telegram channel and compare SHA256SUMS.txt when
available. If you trust the downloaded release, Windows provides a "More info" option
from which you can choose to run it.

IF FIRST-RUN SETUP FAILS
- Make sure the computer has Internet access.
- Make sure GitHub and the listed upstream download providers are reachable.
- Run START_NOTLIGHT.bat again.
- If it still fails, report the error text here:
  https://github.com/waxips/NotLight/issues

SOURCE CODE AND LICENSES
Source code: https://github.com/waxips/NotLight
Project news: https://t.me/notlight_official
NotLight source license: GPL-3.0-or-later
Third-party notices and license texts are included in this folder.


NOTLIGHT ДЛЯ WINDOWS — БЫСТРЫЙ ЗАПУСК
=====================================

1. Полностью распакуйте ZIP в обычную папку, например Документы\NotLight.
2. Дважды нажмите START_NOTLIGHT.bat.
3. При первом запуске нужен интернет. Скрипт сам скачает закреплённые компоненты
   для видео, PDF и формул напрямую у их поставщиков и проверит архивы перед установкой.
4. После настройки NotLight запустится автоматически.
5. В дальнейшем запускайте тот же START_NOTLIGHT.bat — повторно скачивать уже
   установленные компоненты не потребуется.

Не запускайте программу прямо из ZIP и не переносите отдельно один EXE.
Если Windows показывает SmartScreen, сначала убедитесь, что архив скачан из
официального GitHub-релиза или Telegram-канала проекта и при возможности сверьте
SHA256SUMS.txt. Сборка пока не подписана платным сертификатом, поэтому предупреждение
Windows само по себе возможно даже для неизменённого файла.

Если первый запуск не смог скачать зависимости, проверьте интернет и повторите
START_NOTLIGHT.bat. Ошибку можно сообщить здесь:
https://github.com/waxips/NotLight/issues

Исходный код: https://github.com/waxips/NotLight
Новости проекта: https://t.me/notlight_official
