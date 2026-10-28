# Вход в DATA.OUT: VK ID, Яндекс ID, аккаунт на сайте, гость

Сайт игры: **https://artemiylakin-debug.github.io/Kod-Clod/**

Без этой настройки игра уже работает: все 21 уровень, прогресс хранится в браузере.
Когда настройка сделана, каждый, кто открыл ссылку, сначала видит экран входа:

- **Войти через VK ID** и **Войти через Яндекс ID**;
- **Войти по логину** / **Создать аккаунт** — свой аккаунт прямо на сайте: логин и пароль,
  без почты, телефона и сторонних компаний;
- **Играть как гость** — без входа, прогресс только в этом браузере. Выбор «гость» живёт
  до закрытия вкладки: по новой ссылке экран входа появится снова.

Вошедшие игроки получают прогресс на любом устройстве и место в общей таблице рекордов.
Если гость потом войдёт, его прогресс перейдёт в аккаунт.

Аккаунты и рекорды хранятся в **Supabase** — бесплатной облачной базе (карта не нужна).
Для VK ID, Яндекс ID и регистрации на сайте в проекте есть небольшая серверная функция
`online/ru-login.ts`. Google и Apple можно добавить позже (шаги 5 и 6).

> **Про ключи.** В `online-config.js` пишутся только открытые значения (адрес проекта,
> ключ `anon public`, ID приложений) — их и так видит любой, кто откроет сайт.
> Секретные ключи (Client secret Яндекса и Google, ключ `service_role`/`secret` Supabase)
> вводи только в настройках Supabase. Не вставляй их в файлы репозитория и не присылай в чат.

**Порядок:** шаги 1, 2 и 7 — и уже работают аккаунты на сайте и гости. Потом шаги 3 и 4
добавят VK ID и Яндекс ID.

---

## 1. Supabase — база и аккаунты

1. Зарегистрируйся на **supabase.com** → **New project**. Название — `data-out`, пароль базы
   придумай и сохрани у себя, регион — ближайший к игрокам (например, Frankfurt).
2. **SQL Editor → New query** → вставь весь файл `online/schema.sql` → **Run**.
   Появится таблица `progress` для прогресса и рекордов.
3. **Authentication → URL Configuration**:
   - **Site URL**: `https://artemiylakin-debug.github.io/Kod-Clod/`
   - **Redirect URLs** → Add URL: `https://artemiylakin-debug.github.io/Kod-Clod/`
4. **Authentication → Sign In / Providers → Email** — должен быть включён: по нему входят
   аккаунты на сайте, и через него функция `ru-login` заводит игроков из VK и Яндекса.
   Писем никто не получает, поэтому «Confirm email» можно не трогать: функция сама
   подтверждает аккаунты, которые создаёт.
5. **Project Settings → API Keys** (или **Data API**): скопируй
   - **Project URL** — вида `https://abcd1234.supabase.co`;
   - ключ **anon public** (у новых проектов он может называться **publishable**).

   Впиши оба в `online-config.js` → `supabaseUrl` и `supabaseKey`.

## 2. Функция ru-login (регистрация на сайте, VK ID и Яндекс ID)

1. **Edge Functions → Deploy a new function → Via Editor**.
2. Имя функции: `ru-login`. Сотри пример и вставь весь файл `online/ru-login.ts` → **Deploy**.
3. В настройках функции выключи **Verify JWT** (Enforce JWT verification) → Save.
4. **Edge Functions → Secrets** → добавь `SITE_ORIGIN` = `https://artemiylakin-debug.github.io`.
   Остальные секреты (`VK_APP_ID`, `YANDEX_CLIENT_ID`, `YANDEX_CLIENT_SECRET`) — на шагах 3 и 4.

Если функцию обновили (новая версия `ru-login.ts` в репозитории) — открой её в Supabase,
вставь файл заново и нажми **Deploy**.

## 3. VK ID

1. Открой **id.vk.com/about/business** → войди → **Создать приложение**.
2. Платформа — **Web**. Название — `DATA.OUT`.
3. **Базовый домен**: `artemiylakin-debug.github.io`
4. **Доверенный Redirect URL**: `https://artemiylakin-debug.github.io/Kod-Clod/`
5. Скопируй **ID приложения** → `online-config.js` → `vkAppId` и в секрет функции `VK_APP_ID`.

## 4. Яндекс ID

1. Открой **oauth.yandex.ru** → **Создать приложение** (тип — для веб-сервисов).
2. Права (доступы): **«Доступ к логину, имени и фамилии, полу»**.
3. **Redirect URI**: `https://artemiylakin-debug.github.io/Kod-Clod/`
4. Скопируй **ClientID** → `online-config.js` → `yandexClientId` и в секрет `YANDEX_CLIENT_ID`.
5. **Client secret** → только в секрет `YANDEX_CLIENT_SECRET`.

## 5. Google (позже)

1. Открой **console.cloud.google.com** → создай проект `DATA.OUT`.
2. **APIs & Services → OAuth consent screen** (Google Auth Platform): тип **External**,
   название `DATA.OUT`, почта для связи — твоя. Опубликуй приложение (**Publish app**),
   иначе войти смогут только тестовые пользователи.
3. **Credentials → Create credentials → OAuth client ID → Web application**:
   - **Authorized JavaScript origins**: `https://artemiylakin-debug.github.io`
   - **Authorized redirect URIs**: `https://ТВОЙ-ПРОЕКТ.supabase.co/auth/v1/callback`
     (точный адрес Supabase показывает на странице провайдера Google, шаг 4).
4. В Supabase: **Authentication → Sign In / Providers → Google** → включи, вставь
   **Client ID** и **Client secret** → Save.
5. В `online-config.js` поставь `google: true` — на экране входа появится кнопка Google.

## 6. Apple (по желанию)

Нужен платный аккаунт разработчика Apple (Apple Developer Program, $99 в год).
Если он есть: в Supabase **Authentication → Providers → Apple** есть пошаговая инструкция,
после неё поставь `apple: true` в `online-config.js`.

Отдельного входа через Samsung, Xiaomi, Huawei или Honor нет: эти компании не дают простой
вход для сайтов. Владельцы Android-телефонов могут войти через VK ID, Яндекс ID, логин на
сайте или Google.

## 7. Включить на сайте

Отредактируй `online-config.js` прямо на GitHub (значок карандаша → **Commit changes**).
Через минуту GitHub Pages обновит сайт. Проверь:

1. Открой сайт — появится экран входа. Кнопки VK и Яндекса видны, только когда в
   `online-config.js` вписаны их ID.
2. **Создать аккаунт** → придумай логин и пароль → **Создать и войти**. Это заодно проверка,
   что Supabase открывается: сделай её **без VPN** — если аккаунт создался, сервер доступен
   игрокам из России.
3. Сыграй уровень, проиграй — в **Рекордах** появится твоя строка (имя по умолчанию — логин,
   поменять его можно в **Аккаунте**).
4. Открой сайт на другом устройстве и войди тем же способом — уровни и облик подтянутся.

Если вход не проходит, текст ошибки показывается на экране входа. Частые причины:

- «Нет связи с сервером» — Supabase недоступен из этой сети (проверь с VPN и без) или
  неверно вписан `supabaseUrl`;
- «Не получилось: …» при создании аккаунта — функция `ru-login` не развёрнута, у неё не
  выключен Verify JWT или неверный `SITE_ORIGIN`;
- VK или Яндекс пишут об ошибке адреса — Redirect URL не совпадает с адресом сайта до символа
  (важна косая черта в конце).

Пароли аккаунтов на сайте восстановить нельзя: почты у них нет. Забывший пароль игрок
просто создаёт новый аккаунт.
