# Проверки сборки

10 октября 2026, Supraworld build 12678, Windows / Steam, Unreal Engine 5.7.4.

- После удаления проверки инвентаря через преобразование soft-reference и изменений OutlineSettings / ForceVolatile игра запускалась и работала около двух минут с включёнными маяками и открытым меню Alt+H. Новых дампов за этот интервал не появилось. Проверку остановил пользователь.
- Фильтрация открытых яиц, собранных страниц и выключение категорий проверены отдельно на Lua-моделях объектов.
- Дополнительная фильтрация по взятой награде SpawnedShopItem / внутреннему ToyEgg проверена на Lua-моделях; после этого изменения игра не запускалась.
- Разнесение 16 наложенных подписей и синтаксис модулей проверены отдельно.
- Проверены SHA256 встроенного пакета, установка в изолированную папку, сохранение настроек и других модов, точный откат.

Это ограниченная проверка, а не гарантия отсутствия вылетов при длительной игре. Проверка содержимого инвентаря через Conv_SoftObjRefToSoftObjPath удалена: она предшествовала вылету UE4SS с неподдерживаемым Utf8StrProperty. Поиск скрывает яйца по состоянию объектов и награды; наличие способности, выданной отдельно от яйца, не определяется.

## 2026-10-13 update

Lua model tests passed for unchanged eggs, hidden actors, observed rewards subsequently destroyed, and secret-volume duplicates within 1.5 metres of eggs. All bundled Lua files compile. These changes were not tested in-game. Proximity filtering can suppress unrelated nearby secrets; inventory ownership is not queried. A reward destroyed before the first scan may remain undetectable if the egg has no retained collected state.
