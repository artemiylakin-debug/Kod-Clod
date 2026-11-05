# DATA.OUT — плагин для Claude Code

Claude делает уровни для [DATA.OUT](https://artemiylakin-debug.github.io/Kod-Clod/): читает правила карты,
смотрит уровни сообщества и рекорды, проверяет свою карту и кладёт черновик в твой аккаунт —
в игре он появится в «Сообщество» → «Мои уровни» → «От ИИ». Ты проходишь его и публикуешь сам.

## Установка

В Claude Code:

```
/plugin marketplace add artemiylakin-debug/Kod-Clod
/plugin install data-out@data-out
```

(Claude Code 2.1.275 и новее — одной командой: `/plugin install data-out --marketplace artemiylakin-debug/Kod-Clod`.)

При установке плагин спросит **ключ ИИ** — его создают в игре: «Сообщество» или «Аккаунт» →
«Подключить ИИ» → «Создать ключ». Ключ хранится в защищённом хранилище Claude Code. Без ключа Claude
только смотрит уровни и рекорды. Сменить ключ — `/plugin configure data-out@data-out`.

## Что внутри

- сервер MCP игры `data-out` (`.mcp.json`) — инструменты описаны в [online/MCP.md](../online/MCP.md);
- `/data-out:level <что сделать>` — новый уровень по описанию, например `/data-out:level арена с роутерами и двумя турелями`;
- `/data-out:review <какой уровень>` — разбор уровня и улучшения.

Опубликовать уровень ИИ не может: так в сообществе не бывает непроходимых уровней.
