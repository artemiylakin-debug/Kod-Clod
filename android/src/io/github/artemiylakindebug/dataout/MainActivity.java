package io.github.artemiylakindebug.dataout;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * DATA.OUT для Android. Одно окно на весь экран (без верхней шторки и нижних кнопок), в нём — игра с сайта.
 * Игра та же, что на сайте: вход, прогресс и база Supabase — общие, обновления приходят с сайта сами.
 * Игра узнаёт приложение по строке «DataOutApp/…» в User-Agent: прячет кнопки «весь экран» и «скачать»,
 * а кнопку «назад» телефона отдаёт в appBack() игры.
 */
public class MainActivity extends Activity {
    static final String HOME = "https://artemiylakin-debug.github.io/Kod-Clod/";
    static final String APP_VERSION = "1.0";

    private WebView web;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Window w = getWindow();
        w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        web.setBackgroundColor(Color.rgb(243, 246, 250));
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setTextZoom(100);
        s.setUserAgentString(s.getUserAgentString() + " DataOutApp/" + APP_VERSION);
        // без сети — страница из кэша: кто уже входил, играет и без интернета (прогресс досохранится потом)
        s.setCacheMode(online() ? WebSettings.LOAD_DEFAULT : WebSettings.LOAD_CACHE_ELSE_NETWORK);

        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                return openOutside(r.getUrl());
            }

            @Override
            public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                if (r.isForMainFrame()) showOffline();
            }
        });

        if (state != null) web.restoreState(state);
        if (web.getUrl() == null) web.loadUrl(HOME);
    }

    // игра, вход и оплата остаются в приложении; остальные ссылки — в браузере телефона
    private boolean openOutside(Uri u) {
        String scheme = u.getScheme() == null ? "" : u.getScheme();
        String host = u.getHost() == null ? "" : u.getHost();
        if (scheme.equals("https") && (host.equals("artemiylakin-debug.github.io") || host.endsWith(".supabase.co")
                || host.equals("yoomoney.ru") || host.endsWith(".yoomoney.ru")
                || host.equals("vk.com") || host.endsWith(".vk.com") || host.equals("id.vk.ru") || host.endsWith(".vk.ru")
                || host.endsWith(".yandex.ru") || host.endsWith(".yandex.com"))) {
            return false;
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, u));
        } catch (Exception ignored) {
        }
        return true;
    }

    private boolean online() {
        try {
            ConnectivityManager cm = (ConnectivityManager) getSystemService(Context.CONNECTIVITY_SERVICE);
            NetworkInfo n = cm == null ? null : cm.getActiveNetworkInfo();
            return n != null && n.isConnected();
        } catch (Exception e) {
            return true;
        }
    }

    private void showOffline() {
        String html = "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                + "<body style='margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#f3f6fa;"
                + "color:#0b2545;font-family:sans-serif;text-align:center'><div style='padding:24px'>"
                + "<h2 style='margin:0 0 8px'>НЕТ СВЯЗИ</h2>"
                + "<p>DATA.OUT не смог открыться: проверь интернет.<br>Прогресс хранится в аккаунте — он никуда не делся.</p>"
                + "<button onclick=\"location.href='" + HOME + "'\" style='font-size:18px;font-weight:bold;padding:12px 28px;"
                + "border-radius:14px;border:3px solid #0b2545;background:#22c55e;color:#fff'>Повторить</button></div></body></html>";
        web.loadDataWithBaseURL("https://artemiylakin-debug.github.io/offline", html, "text/html", "utf-8", null);
    }

    @SuppressWarnings("deprecation")
    private void immersive() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) immersive();
    }

    // «назад» телефона: игра сама решает — пауза, предыдущий экран; на главном экране приложение сворачивается
    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (web == null) {
            super.onBackPressed();
            return;
        }
        web.evaluateJavascript("(window.appBack&&window.appBack())?'1':'0'", new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String v) {
                if (!"\"1\"".equals(v)) moveTaskToBack(true);
            }
        });
    }

    @Override
    protected void onPause() {
        if (web != null) {
            // свернули приложение посреди уровня — пауза, как на сайте при уходе со вкладки
            web.evaluateJavascript("window.appPause&&window.appPause()", null);
            web.onPause();
        }
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
        immersive();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) web.saveState(out);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
