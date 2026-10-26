# Производительность чистого ядра

Команда: `python tests/performance_native.py`. Linux x86_64, системная Lua 5.4, без Roblox engine. 12 матчей, 1000 шагов по 0,05 с (50 секунд игрового времени).

- environment: system Lua 5.4; no Roblox engine
- matches: 12
- ticks: 1000
- simulated_seconds: 50
- batch_step_p50_ms: 0.312
- batch_step_p95_ms: 0.838
- load_12_profiles_seconds: 0.05168
- lua_heap_before_kib: 330.46
- lua_heap_after_kib: 14764.92

Heap измерен после GC и включает живые профили и replay; разница не доказывает утечку. Это микроизмерение Lua, не live-нагрузочный тест Roblox. Frame time клиента, FPS ПК/телефона, реальный трафик, память/Instances Roblox, загрузка и throughput DataStore, 30-минутные утечки: NOT RUN. Нет измеренного сравнения до/после, заявлений роста FPS нет.

Catch-up ограничен 0,25 с, 20Hz fixed step и 10Hz snapshot, AI отдельно; revision patches/resync; ограниченные буферы. 12 Roblox-клиентов не подтверждены. Для закрытого пилота MaxPlayers=1 — ограничение риска, не измеренная гарантия.
