# QA 2026-10-24

Среда: Linux x86_64, Python 3, системная Lua 5.4 через ctypes. Это не Roblox Studio. Команда: `python tests/native_check.py`; сырые результаты: NATIVE_TEST_RESULTS.json, tests/latest_run.txt.

| Проверка | Статус | Наблюдаемый результат |
|---|---|---|
| syntax Audio.lua | PASS | assertions passed; 0.0 с |
| syntax AudioConfig.lua | PASS | assertions passed; 0.0 с |
| syntax Branding.lua | PASS | assertions passed; 0.0 с |
| syntax Career.lua | PASS | assertions passed; 0.001 с |
| syntax CareerScreens.lua | PASS | assertions passed; 0.001 с |
| syntax Client.client.lua | PASS | assertions passed; 0.0 с |
| syntax Diagnostics.lua | PASS | assertions passed; 0.0 с |
| syntax Economy.lua | PASS | assertions passed; 0.0 с |
| syntax EconomyConfig.lua | PASS | assertions passed; 0.0 с |
| syntax Input.lua | PASS | assertions passed; 0.0 с |
| syntax Loans.lua | PASS | assertions passed; 0.0 с |
| syntax Locales.lua | PASS | assertions passed; 0.001 с |
| syntax Localization.lua | PASS | assertions passed; 0.0 с |
| syntax Market.lua | PASS | assertions passed; 0.0 с |
| syntax Match.lua | PASS | assertions passed; 0.001 с |
| syntax MatchConfig.lua | PASS | assertions passed; 0.0 с |
| syntax MatchView.lua | PASS | assertions passed; 0.0 с |
| syntax Monetization.lua | PASS | assertions passed; 0.0 с |
| syntax MonetizationConfig.lua | PASS | assertions passed; 0.0 с |
| syntax Players.lua | PASS | assertions passed; 0.0 с |
| syntax Records.lua | PASS | assertions passed; 0.0 с |
| syntax Results.lua | PASS | assertions passed; 0.0 с |
| syntax Server.server.lua | PASS | assertions passed; 0.0 с |
| syntax Storage.lua | PASS | assertions passed; 0.0 с |
| syntax StudioQA.lua | PASS | assertions passed; 0.0 с |
| syntax Tournaments.lua | PASS | assertions passed; 0.0 с |
| syntax Training.lua | PASS | assertions passed; 0.0 с |
| syntax UI.lua | PASS | assertions passed; 0.0 с |
| syntax World.lua | PASS | assertions passed; 0.0 с |
| syntax WorldConfig.lua | PASS | assertions passed; 0.0 с |
| 320 stable original clubs, 20 persistent divisions and 30 symmetric rounds | PASS | assertions passed; 0.006 с |
| 96 and 32 real-club cup fields, preliminary seeding and five-round brackets | PASS | assertions passed; 0.002 с |
| International qualification is unique with explicit duplicate-winner fallback | PASS | assertions passed; 0.004 с |
| Unified fixture order, no menu RNG changes, duplicate finalization rejected | PASS | assertions passed; 0.004 с |
| 35 seasons preserve identities, 16-club divisions, reciprocal promotion and growing records | PASS | assertions passed; 0.367 с |
| Simulated penalty shootouts record football kicks and reproducible winners | PASS | assertions passed; 0.002 с |
| 22 role-adjusted footballers and venue semantics | PASS | assertions passed; 0.001 с |
| Halftime and extra-time switch ends | PASS | assertions passed; 0.0 с |
| Goals, assists and own goals are user-oriented on away venue | PASS | assertions passed; 0.0 с |
| Throw-ins, corners and goal kicks have correct beneficiary | PASS | assertions passed; 0.0 с |
| Simplified offside on targeted forward pass | PASS | assertions passed; 0.0 с |
| Red cards remove players; substitutions cannot restore them | PASS | assertions passed; 0.0 с |
| Penalty shootout decisions, early finish and no repeated finish | PASS | assertions passed; 0.0 с |
| Snapshots and mode switching do not advance RNG | PASS | assertions passed; 0.046 с |
| Sprinting is bounded by stamina; invalid values cannot poison state | PASS | assertions passed; 0.003 с |
| Deterministic complete simulation and bounded replay/events | PASS | assertions passed; 1.031 с |
| career 31 seasons with forfeit and duplicate finalization | PASS | assertions passed; 0.416 с |
| goalkeeper reservation prevents a hole after roster turnover | PASS | assertions passed; 0.002 с |
| free agent immediate resale and no repeat purchase | PASS | assertions passed; 0.003 с |
| legacy v1 migration preserves club assets and does not repeat | PASS | assertions passed; 0.004 с |
| localization: locale, fallback, numbers and expanded strings | PASS | assertions passed; 0.002 с |
| training isolation, fixed challenge, exact-once cosmetics and tutorial steps | PASS | assertions passed; 0.017 с |
| record categories, anomalous values, monotonic writes and throttled reads | PASS | assertions passed; 0.003 с |
| automatic XI selects strongest eligible goalkeeper and roles | PASS | assertions passed; 0.003 с |
| highlights control is limited to episodes and shootouts stay manual | PASS | assertions passed; 0.005 с |
| full roster suspensions cannot deadlock finalization or farm technical defeats | PASS | assertions passed; 0.014 с |
| calendar recovery is free, capped and preparation charges wages once | PASS | assertions passed; 0.018 с |
| substitution preserves departed ratings, fitness and substitute experience | PASS | assertions passed; 0.003 с |
| former clubs age their squads and retain bounded detail without losing cash | PASS | assertions passed; 0.013 с |
| board rewards settle once, active manager contract blocks job cycling, club debts remain | PASS | assertions passed; 0.074 с |
| outgoing loans reserve squad depth, split wages, advance once and block duplicate sales | PASS | assertions passed; 0.017 с |
| branding filters before mutation and enforces names and premium entitlement | PASS | assertions passed; 0.002 с |
| own and academy scouting use regional reports with exact-once charges | PASS | assertions passed; 0.002 с |
| set-piece selection, four formation lines, shootout order and red-card keeper substitution | PASS | assertions passed; 0.004 с |
| test_storage.py adapter scenarios | PASS | assertions passed; 0.002 с |
| test_monetization.py adapter scenarios | PASS | assertions passed; 0.001 с |
| modular UI construction and grouped pages (mock, not Studio) | PASS | assertions passed; 0.044 с |
| Полный UI и ввод в Roblox | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| Телефон в двух ориентациях и реальный multitouch | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| Два Studio-клиента и независимые карьеры | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| Live DataStore, авария сервера, восстановление pending | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| Реальная оплата, receipt и pass после перезахода | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| Cloud-переводы, CJK, длинные строки на экране | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |
| 12 реальных матчей, FPS, сеть, память и 30 минут утечек | NOT RUN | Нужны Studio/опубликованный закрытый place/устройства |

XML/ZIP и соответствие исходников проверяются `python build.py`. Повторная сборка проверяется SHA256. Старый QA и старые тесты сохранены в baseline и не объявлены пройденными новой версией.

Приёмка мастер-промпта не завершена: Studio, устройства и live-сервисы здесь недоступны. Границы проверки — DEVELOPMENT_GAPS_RU.md; порядок проверки — RELEASE_CHECKLIST_RU.md.