# Hub ambient phrases

The runtime no longer loads a separate `phrases.json`. All forty Hub ambient phrases are canonical localization entries under `ambient.phrase.001` … `ambient.phrase.040` and are resolved exclusively through `NotLightL10n`. Russian is the completeness baseline in `localization/core/ru.json`; retained non-Russian bundles may carry their existing translations and fall back to Russian for missing keys.

The phrase texts remain dedicated to the public domain under **CC0-1.0** for easy reuse in forks and community builds. The localization service and surrounding NotLight source code remain under the project's normal GPL-3.0-or-later license.
