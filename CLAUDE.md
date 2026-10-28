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
  (VK ID, Яндекс ID, регистрация по логину) и `yoomoney-hook.ts` (поддержка игры), скрипт
  `setup-supabase.mjs` и ручная инструкция `SETUP.md`.
- `TERMS.md` — пользовательское соглашение. Его текст встроен в `index.html` (`<template id="terms-tpl">`)
  и в `terms.html`; при правке соглашения обновлять все три места и номер редакции.

## База

Создана 28.10.2026: проект Supabase `data-out` (ref `lnkekrusqjdroomcufen`, регион `eu-central-1`),
таблицы из `schema.sql`, функции `ru-login` и `yoomoney-hook` (Verify JWT выключен). Управлять удобнее
всего через коннектор Supabase (MCP). Секреты функций (`VK_APP_ID`, `YANDEX_CLIENT_ID`,
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
