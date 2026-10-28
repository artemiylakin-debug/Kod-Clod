// Настройки входа для DATA.OUT на GitHub Pages.
// Здесь только ОТКРЫТЫЕ значения — их и так видит каждый, кто откроет сайт.
// Секретные ключи (Client secret Google и Яндекса, service_role Supabase, секрет уведомлений ЮMoney) сюда НЕ пиши:
// они хранятся только в Supabase. Как всё получить — online/SETUP.md.
// Пока supabaseUrl или supabaseKey пустые, игра работает без аккаунтов, прогресс — в браузере.
// Когда оба заполнены, сайт при входе просит войти (VK ID, Яндекс ID, логин на сайте) или играть гостем.
window.DATA_OUT_ONLINE = {
  supabaseUrl: 'https://lnkekrusqjdroomcufen.supabase.co',      // адрес проекта Supabase, например https://abcd1234.supabase.co
  supabaseKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imxua2VrcnVzcWpkcm9vbWN1ZmVuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMxOTg2NjMsImV4cCI6MjEwODc3NDY2M30.VVf_UCfOzdDWU4YZgTM6J-ieRkyX628evwEjcp2qRuE',      // публичный ключ «anon public» (Project Settings → API Keys)
  vkAppId: '',          // ID приложения VK ID
  yandexClientId: '',   // ClientID приложения Яндекс ID
  google: false,        // true — когда вход через Google включён в Supabase
  apple: false,         // true — когда включён вход через Apple (нужен платный аккаунт разработчика Apple)
  yoomoney: '',         // номер кошелька ЮMoney для поддержки игры (с набором «Поддержка»): 15–16 цифр, начинается с 4100
  donateUrl: ''         // по желанию: ссылка на страницу поддержки автора (Boosty, CloudTips…) — без набора
};
