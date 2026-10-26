# Локализация Touchline Dynasty

Исходный язык: English (`en-us`). Полные локальные словари находятся в `localization/strings.tsv`; `python localization/build_locales.py` воспроизводимо создаёт `src/Locales.lua`, JSON и таблицы CSV. Встроенные русский и украинский переводы работают без облачного сервиса. Персональные имена и названия клубов являются параметрами: система их не переводит.

`Localization.new({locale='auto', robloxLocale=LocalizationService.RobloxLocaleId})` выбирает язык по Roblox locale. Страна, IP и системный регион не используются. Ручная настройка передаётся серверу и хранится в настройках профиля. Для `auto` и неподдерживаемых языков есть безопасный English fallback. Арабский/RTL не заявлены. Новые события содержат ключ и параметры; строки истории старой версии остаются читаемыми через legacy fallback.

Облачный перевод запрашивается асинхронно через `GetTranslatorForPlayerAsync` либо `GetTranslatorForLocaleAsync`; ошибки, отсутствие ключа, завершение запроса после 4 секунд и ответ для старого выбранного языка не блокируют игру. `Translator:FormatByKey` переводит только шаблон. `L.installTable(parent)` создаёт локальную `LocalizationTable` через `SetEntries`, без устаревших API.

## Действия владельца опубликованного тестового experience

1. Открыть Localization в Creator Dashboard именно тестового experience; установить Source language English. Сохранить резервную копию текущей cloud table, если она уже существует.
2. Импортировать `localization/Roblox_Cloud_Import.csv` в Cloud Localization Table. В таблице есть английский Source, уникальные Key/Context и готовые RU-значения; пустые значения приоритетных языков предназначены для перевода. При отличиях заголовков в текущем экспортном шаблоне Dashboard перенести соответствующие столбцы, сохраняя Key/Source/Context. Не заменять имена клубов переводами.
3. В Settings включить **Use Translated Content**. Во вкладке Languages включить **Experience Strings & Products** для Spanish, Portuguese, Polish, German, French, Turkish, Japanese и Korean. Переводы названия/описания experience (`Experience Information`) включаются отдельно.
4. Учесть исходную и месячную квоты перевода; дождаться появления значений и проверить их с носителями языка. Существующие ручные переводы не перезаписываются автоматически. Включение автоматического сервиса в этой среде не выполнялось.
5. Украинского нет в опубликованном Roblox списке automatic translation на дату проверки; игра использует собственный словарь. `Ukrainian_Manual.csv` предназначен для редакторской проверки и не выдаётся за включённый облачный язык.
6. Automatic Text Capture — необязательный дополнительный инструмент. В Dashboard переключатель **Capture text from experience UI while users play**; в Studio — Window → Localization → Localization Tools → Automatic Text Capture. Ключи игры уже подготовлены для импорта; имена и динамические параметры не следует собирать как самостоятельные строки. UI использует ключевое форматирование и не полагается на AutoLocalize.
7. В опубликованном тестовом place проверить автоматический язык Roblox и ручную смену EN/RU/UK/приоритетных облачных языков, затем перезаход и сохранение выбора. Убедиться, что ошибка облачного сервиса даёт английский текст и не зависание.

## Выполненные и оставшиеся проверки

`python tests/test_localization.py` проверяет полноту словарей, совпадение параметров, правила множественного числа EN/RU/UK, формат чисел/дат, legacy историю, неразрушающее обращение с CJK-параметрами, псевдолокализацию с расширением 40–60% для строк длиной от 10 символов, timeout/fallback/stale/error адаптера и воспроизводимость экспорта. Это Lua и тестовые адаптеры, не Roblox Studio.

NOT RUN до Studio/device playtest: отображение японских/корейских глифов и переносов; читаемость Noto/Gotham fallback; кнопки и длинные строки при `qps-ploc` и увеличенном тексте; оба положения телефона; live cloud lookup; настройки Dashboard. Псевдолокаль проверяет длину программно, но не доказывает правильную физическую компоновку.

API и поддержка языков сверены с официальной документацией 23.10.2026:

- [Automatic translations](https://create.roblox.com/docs/production/localization/automatic-translations)
- [Manual translations and cloud table](https://create.roblox.com/docs/production/localization/manual-translations)
- [LocalizationService](https://create.roblox.com/docs/reference/engine/classes/LocalizationService)
- [Translator.FormatByKey](https://create.roblox.com/docs/reference/engine/classes/Translator)
- [LocalizationTable.SetEntries](https://create.roblox.com/docs/reference/engine/classes/LocalizationTable)
