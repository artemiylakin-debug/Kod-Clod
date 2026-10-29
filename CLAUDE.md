# DATA.OUT — заметки для Claude

Игра-аркада «DATA.OUT v5.0 — побег из корзины». Автор общается по-русски; обращаться на «вы».
Автор просил: всё должно быть и в артефакте — https://claude.ai/artifact/445HdLoTZ8KQ1YV6iHBo7k
(его содержимое — то, что лежит в `index.html` между `<body>` и `</body>`).

## Что где

- `index.html` — вся игра одним файлом. Сайт: https://artemiylakin-debug.github.io/Kod-Clod/
  (GitHub Pages из ветки `main`). Работа идёт в ветке `claude/data-out-online`, `main` перематывается до неё.
- `online-config.js` — только открытые настройки: адрес Supabase, ключ `anon`, ID приложений VK и Яндекса,
  номер кошелька ЮMoney. Секреты (`service_role`, токены, Client secret) в репозиторий не кладутся никогда.
- `online/` — сервер на Supabase: `schema.sql` (можно запускать повторно), функции `ru-login.ts`
  (VK ID, Яндекс ID, регистрация по логину), `yoomoney-hook.ts` (поддержка игры) и `mcp.ts`
  (сервер MCP для ИИ-помощников, см. `MCP.md`), скрипт `setup-supabase.mjs` и ручная инструкция `SETUP.md`.
  Уровень игрока — карта из клеток 32×20 (формат 2, `map` из 20 строк по 32 символа); правила карты
  повторены в `mcp.ts` (`cleanLevel`) и в `index.html` (`normLevel`, `mapToCfg`) — менять вместе.
  Логин на сайте — русские или латинские буквы, цифры, пробел, «_», «-». Латинский логин входит по адресу
  `<логин>@player.data-out.app`, остальные — по `u<первые 40 hex SHA-256 от «data-out:<логин>»>@player.data-out.app`;
  считают одинаково `siteEmail` в `index.html` и в `ru-login.ts` — менять только вместе.
- Гонка (мультиплеер) — раздел «ГОНКА» в `index.html`: свой клиент Supabase Realtime (протокол Phoenix),
  каналы `dataout-lobby` и `dataout-race-<код>`, без таблиц; см. `online/SETUP.md`, раздел 11. Музыка уровней —
  раздел «МУЗЫКА»: синтез в Web Audio, темы по актам (`MUS_THEMES`), и записанные треки из `music/`.
- Уровней 500 в 26 актах (`ACTS`, `LEVELS`); акты 12–26 (уровни 201–500) собраны генератором по правилам
  сочетания опасностей, но хранятся в `index.html` обычными строками — править можно руками. При новом акте
  добавлять: `ACTS`, `LEVELS`, `ACT_STORY`, `MUS_THEMES`, треки `music/aNN-*`, `THEMES` в `online/mcp.ts`
  и предел `unlocked` в базе (`progress_unlocked_check`, сейчас до 500).
- Сложность официальных уровней — `DIFF`, уровней сообщества — `DIFF_COMM` (прежние множители);
  в гонке — сложность, выбранная хозяином комнаты (`RACE_DIFF`).
- `music/` — записанная музыка уровней: по три трека на акт и трек босса (только CC0, источники — в `music/CREDITS.md`).
  В артефакте файлов нет (хранилище артефакта не принимает звук), там играет синтезатор из `index.html`.
- Защита 6.0: `online/security-6.0.sql` — триггер `progress_guard` (правдоподобие прогресса, владение
  обликом), отзыв лишних прав, журнал `signup_log` для ограничения регистраций в `ru-login`.
  Каталог облика в функции `data_out_items()` — копия `SKIN_COLORS`/`SKIN_SHAPES`/`TRAILS`/`HATS` и концов
  `ACTS`: при новых предметах или актах пересобрать (`node tools/cosmetics-catalog.mjs`) и проверить
  `node tools/check-catalog.mjs`, потом применить файл в базе. `online/security-6.0-test.sql` проверяет
  защиту на живой базе и всё откатывает. CSP сайта — в `<head>` `index.html` (адрес базы в `connect-src`).
- Аксессуары — `HATS` и `drawHat`; 13–24 добавлены в 6.0. Ключ сохранения `dataout-v5` не менять.
- Наряды — `save.outfits` (до `OUTFIT_MAX`, только номера предметов), раздел «НАРЯДЫ» в «Облике»; на сайте
  хранятся в `user_metadata.outfits` аккаунта, в артефакте — в личном документе базы. След 11 — «ХВОСТ ЧЁРТА» (`drawTail`).
  Покупка наряда в один клик — `buyOutfit`/`outfitBuyHTML` (кнопка `ofbuy` при примерке, `tryOutfit`): покупает
  все недостающие вещи с ценой по обычной сумме цен, вещи за акт и за поддержку не продаёт.
- `TERMS.md` — пользовательское соглашение. Его текст встроен в `index.html` (`<template id="terms-tpl">`)
  и в `terms.html`; при правке соглашения обновлять все три места и номер редакции.

## База

Создана 28.10.2026: проект Supabase `data-out` (ref `lnkekrusqjdroomcufen`, регион `eu-central-1`),
таблицы из `schema.sql`, функции `ru-login` и `yoomoney-hook` (Verify JWT выключен). Потом предел
уровней в `progress` поднят до 200 (миграция `allow_200_levels`), добавлены профили, уровни
сообщества, лайки, запуски и администраторы (миграции `community_profiles_admin`, `is_admin_invoker`),
ключи MCP и черновики от ИИ (миграция `mcp_keys_and_drafts`, функция `mcp`, Verify JWT выключен).
29.10.2026 (обновление 6.0) развёрнуты новые `ru-login` (версия 3) и `yoomoney-hook` (версия 2).
Миграция `online/security-6.0.sql` ПОКА НЕ ПРИМЕНЕНА: до неё прогнать `online/security-6.0-test.sql`
(всё откатывает). Через коннектор Supabase запросы с `revoke`/`drop` ждут подтверждения автора — если оно
не приходит, автор запускает файлы сам в SQL Editor. До миграции `ru-login` регистрирует без ограничения
числа (журнала `signup_log` ещё нет). Открытая регистрация Supabase («Allow new users to sign up») ещё включена.
Администратор игры — аккаунт автора `artemiy123` (таблица `admins`). Пароль автора не нужен ни для
чего: права выдаются в базе по `user_id`. Управлять удобнее всего через
коннектор Supabase (MCP). Секреты функций (`VK_APP_ID`, `YANDEX_CLIENT_ID`,
`YANDEX_CLIENT_SECRET`, `YOOMONEY_SECRET`) пока не заданы: их значения автор вводит сам в панели Supabase.

## Просьба «создай базу»

1. Проверить, что в окружении есть `SUPABASE_ACCESS_TOKEN` (значение не печатать) и что
   `curl -s -o /dev/null -w '%{http_code}' https://api.supabase.com/v1/organizations` отвечает 401, а не ошибкой прокси.
   Нет токена или домен закрыт — сказать автору, что поправить в настройках окружения, и остановиться.
2. Из корня репозитория: `node online/setup-supabase.mjs`. Скрипт берёт готовый проект `data-out` или
   создаёт новый, выполняет `schema.sql`, разворачивает обе функции, задаёт адрес сайта и вписывает
   адрес и ключ `anon` в `online-config.js`. Скрипт проверен только на макете Management API: если запрос
   падает, сверить с https://supabase.com/docs/reference/api/introduction, исправить скрипт и запустить снова.
3. Проверить вживую, через REST проекта (заголовки `apikey` и `Authorization: Bearer <anon>`):
   регистрация `POST /functions/v1/ru-login` с `{provider:'site', login:'claudetest<случайное>', password}`,
   вход `POST /auth/v1/token?grant_type=password` с почтой `<login>@player.data-out.app`,
   запись `POST /rest/v1/progress?on_conflict=user_id`, чтение таблицы рекордов.
   После проверки удалить тестового игрока: `POST /v1/projects/{ref}/database/query` с
   `delete from auth.users where email = '<login>@player.data-out.app'`.
4. Закоммитить `online-config.js` в `claude/data-out-online`, перемотать `main`, дождаться сборки Pages.
   После этого сайт требует вход: без аккаунта играть нельзя.
5. Рассказать автору, что сделано, и что для кнопок VK ID и Яндекс ID нужны их приложения (шаги 3–4 в `SETUP.md`).
