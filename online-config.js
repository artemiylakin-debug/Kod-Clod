// Настройки входа для DATA.OUT на GitHub Pages.
// Здесь только ОТКРЫТЫЕ значения — их и так видит каждый, кто откроет сайт.
// Секретные ключи (Client secret Google и Яндекса, service_role Supabase) сюда НЕ пиши:
// они хранятся только в Supabase. Как всё получить — online/SETUP.md.
// Пока supabaseUrl или supabaseKey пустые, игра работает без аккаунтов, прогресс — в браузере.
// Когда оба заполнены, сайт при входе просит войти (VK ID, Яндекс ID, логин на сайте) или играть гостем.
window.DATA_OUT_ONLINE = {
  supabaseUrl: '',      // адрес проекта Supabase, например https://abcd1234.supabase.co
  supabaseKey: '',      // публичный ключ «anon public» (Project Settings → API Keys)
  vkAppId: '',          // ID приложения VK ID
  yandexClientId: '',   // ClientID приложения Яндекс ID
  google: false,        // true — когда вход через Google включён в Supabase
  apple: false          // true — когда включён вход через Apple (нужен платный аккаунт разработчика Apple)
};
