# Проверка стилей полного матчевого ядра

Команда: `python tests/style_native.py`. 5×5 сочетаний по 20 seed: 10 домашних и 10 выездных матчей. Все атрибуты и навыки вратаря 70, fitness/form/morale 100, химия 0, нормальная сложность. 500 полных Match.simulate, без ручного управления и Roblox. Сырые результаты: STYLE_RAW.csv.

| Стиль | Соперник | Победы / ничьи / поражения | Голы за / против |
|---|---|---|---|
| possession | possession | 7 / 4 / 9 | 33 / 48 |
| possession | counter | 2 / 3 / 15 | 24 / 62 |
| possession | press | 6 / 3 / 11 | 71 / 89 |
| possession | lowblock | 3 / 4 / 13 | 38 / 88 |
| possession | wings | 6 / 2 / 12 | 66 / 111 |
| counter | possession | 14 / 2 / 4 | 74 / 25 |
| counter | counter | 7 / 5 / 8 | 38 / 46 |
| counter | press | 5 / 2 / 13 | 40 / 64 |
| counter | lowblock | 9 / 5 / 6 | 50 / 34 |
| counter | wings | 13 / 2 / 5 | 133 / 82 |
| press | possession | 15 / 2 / 3 | 156 / 70 |
| press | counter | 15 / 2 / 3 | 70 / 39 |
| press | press | 10 / 1 / 9 | 118 / 115 |
| press | lowblock | 7 / 1 / 12 | 69 / 77 |
| press | wings | 10 / 2 / 8 | 134 / 109 |
| lowblock | possession | 15 / 3 / 2 | 108 / 28 |
| lowblock | counter | 5 / 6 / 9 | 33 / 55 |
| lowblock | press | 12 / 3 / 5 | 79 / 57 |
| lowblock | lowblock | 8 / 6 / 6 | 39 / 34 |
| lowblock | wings | 15 / 0 / 5 | 119 / 81 |
| wings | possession | 10 / 4 / 6 | 88 / 78 |
| wings | counter | 5 / 3 / 12 | 61 / 88 |
| wings | press | 11 / 0 / 9 | 107 / 115 |
| wings | lowblock | 9 / 2 / 9 | 81 / 83 |
| wings | wings | 14 / 0 / 6 | 179 / 159 |

Диагностическая выборка выявляет различия стилей, но 20 seed на пару недостаточно для точных вероятностей. Одинаковые характеристики не делают поведение сторон зеркальным: пользовательская команда и NPC используют разные решения. Матрица не доказывает равную сложность или отсутствие сильнейшей политики. Баланс ручного управления и ощущение тактик требуют playtest.
