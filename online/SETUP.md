# Вход в DATA.OUT: VK ID, Яндекс ID, Google, Apple

Сайт игры: **https://artemiylakin-debug.github.io/Kod-Clod/**

Без этой настройки игра уже работает: все 21 уровень, прогресс хранится в браузере.
Настройка добавляет аккаунты (прогресс на любом устройстве) и общую таблицу рекордов.

Аккаунты и рекорды хранятся в **Supabase** — бесплатной облачной базе (карта не нужна).
Google и Apple Supabase умеет подключать сам, а для VK ID и Яндекс ID в проекте есть
небольшая серверная функция `online/ru-login.ts`.

> **Про ключи.** В `online-config.js` пишутся только открытые значения (адрес проекта,
> ключ `anon public`, ID приложений) — их и так видит любой, кто откроет сайт.
> Секретные ключи (Client secret Google и Яндекса, ключ `service_role`/`secret` Supabase)
> вводи только в настройках Supabase. Не вставляй их в файлы репозитория и не присылай в чат.

---

## 1. Supabase — база и аккаунты

1. Зарегистрируйся на **supabase.com** → **New project**. Название — `data-out`, пароль базы
   придумай и сохрани у себя, регион — ближайший к игрокам (например, Frankfurt).
2. **SQL Editor → New query** → вставь весь файл `online/schema.sql` → **Run**.
   Появится таблица `progress` для прогресса и рекордов.
3. **Authentication → URL Configuration**:
   - **Site URL**: `https://artemiylakin-debug.github.io/Kod-Clod/`
   - **Redirect URLs** → Add URL: `https://artemiylakin-debug.github.io/Kod-Clod/`
4. **Authentication → Sign In / Providers → Email** — должен быть включён (через него
   функция `ru-login` заводит игроков из VK и Яндекса; писем никто не получает).
5. **Project Settings → API Keys** (или **Data API**): скопируй
   - **Project URL** — вида `https://abcd1234.supabase.co`;
   - ключ **anon public** (у новых проектов он может называться **publishable**).

   Впиши оба в `online-config.js` → `supabaseUrl` и `supabaseKey`.

## 2. Функция ru-login (для VK ID и Яндекс ID)

1. **Edge Functions → Deploy a new function → Via Editor**.
2. Имя функции: `ru-login`. Сотри пример и вставь весь файл `online/ru-login.ts` → **Deploy**.
3. В настройках функции выключи **Verify JWT** (Enforce JWT verification) → Save.
4. **Edge Functions → Secrets** → добавь:
   - `SITE_ORIGIN` = `https://artemiylakin-debug.github.io`
   - `VK_APP_ID` = ID приложения VK ID (шаг 3)
   - `YANDEX_CLIENT_ID` и `YANDEX_CLIENT_SECRET` (шаг 4)

## 3. VK ID

1. Открой **id.vk.com/about/business** → войди → **Создать приложение**.
2. Платформа — **Web**. Название — `DATA.OUT`.
3. **Базовый домен**: `artemiylakin-debug.github.io`
4. **Доверенный Redirect URL**: `https://artemiylakin-debug.github.io/Kod-Clod/`
5. Скопируй **ID приложения** → `online-config.js` → `vkAppId` и в секрет `VK_APP_ID`.

## 4. Яндекс ID

1. Открой **oauth.yandex.ru** → **Создать приложение** (тип — для веб-сервисов).
2. Права (доступы): **«Доступ к логину, имени и фамилии, полу»**.
3. **Redirect URI**: `https://artemiylakin-debug.github.io/Kod-Clod/`
4. Скопируй **ClientID** → `online-config.js` → `yandexClientId` и в секрет `YANDEX_CLIENT_ID`.
5. **Client secret** → только в секрет `YANDEX_CLIENT_SECRET`.

## 5. Google

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
5. В `online-config.js` поставь `google: true`.

## 6. Apple (по желанию)

Нужен платный аккаунт разработчика Apple (Apple Developer Program, $99 в год).
Если он есть: в Supabase **Authentication → Providers → Apple** есть пошаговая инструкция,
после неё поставь `apple: true` в `online-config.js`.

Отдельного входа через Samsung, Xiaomi, Huawei или Honor нет: эти компании не дают простой
вход для сайтов. Владельцы Android-телефонов могут войти через Google, VK ID или Яндекс ID.

## 7. Включить на сайте

Отредактируй `online-config.js` прямо на GitHub (значок карандаша → **Commit changes**).
Через минуту GitHub Pages обновит сайт. Проверь:

1. Открой сайт → **Аккаунт** — появятся кнопки входа для настроенных сервисов.
2. Войди, сыграй уровень, проиграй — в **Рекордах** появится твоя строка.
3. Открой сайт на другом устройстве и войди тем же способом — уровни и облик подтянутся.

Если вход не проходит, текст ошибки показывается в окне **Аккаунт**. Частые причины:
Redirect URL в VK, Яндексе или Supabase не совпадает с адресом сайта до символа
(важна косая черта в конце), не задан секрет функции или не выключен Verify JWT.
