# ipAdreses — списки доменов и IP ИИ-сервисов

Объединённые списки доменов и IP для OpenAI (ChatGPT/API), Anthropic (Claude) и Google Gemini. Собираются из публичных источников ([blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script), [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community), [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR)) скриптом `merge.sh` и обновляются автоматически (GitHub Action, ежедневно; можно запустить вручную на вкладке Actions).

В списках есть общие домены вендоров (`algolia.net`, `stripe.com`, `sentry.io`, `intercom.io`, `challenges.cloudflare.com`, `apis.google.com` и др.) — ИИ-сервисы используют их для телеметрии, авторизации, платежей и челленджей Cloudflare. ASN-диапазоны намеренно не включены, чтобы не уводить в туннель чужой трафик.

## Файлы

| Файл | Формат | Назначение |
|---|---|---|
| `domains.txt` | домены, по одному на строку | все сервисы разом — Podkop (Remote Domain Lists), любой клиент |
| `openai-domains.txt` | домены | только OpenAI/ChatGPT — для раздельной маршрутизации |
| `anthropic-domains.txt` | домены | только Anthropic/Claude — для раздельной маршрутизации |
| `gemini-domains.txt` | домены | только Google Gemini — для раздельной маршрутизации |
| `cidrs.txt` | IP/CIDR, по одному на строку | подсети OpenAI — Podkop (Remote Subnet Lists) |
| `singbox-ai.json` | rule-set sing-box, version 3 | все сервисы разом — Podkop, NekoBox, SFI |
| `openai.txt`, `anthropic.txt`, `gemini.txt` | матчеры Xray (`domain:`, `full:`, `regexp:`, ключевые слова) | Xray / init-скрипты |
| `ai-cidrs.txt` | CIDR для Xray | Xray / init-скрипты |

## Использование в Podkop (OpenWrt)

В LuCI откройте нужную секцию Podkop и добавьте:

- **Remote Domain Lists**: `https://raw.githubusercontent.com/Tro48/ipAdreses/main/domains.txt` (или `singbox-ai.json`)
- **Remote Subnet Lists**: `https://raw.githubusercontent.com/Tro48/ipAdreses/main/cidrs.txt`

После сохранения Podkop сам скачивает и периодически обновляет списки. Для Gemini у Podkop есть и встроенный список «Google AI» — подключайте что-то одно, чтобы не дублировать правила.

### Раздельная маршрутизация по серверам

Если выходы имеют разную репутацию (например, один сервер заблокирован у части сервисов), создайте две секции с разными подключениями и по-сервисными списками:

Секция «ai-us» (подключение — VLESS-ссылка американского сервера):

- Remote Domain Lists:
  - `https://raw.githubusercontent.com/Tro48/ipAdreses/main/openai-domains.txt`
  - `https://raw.githubusercontent.com/Tro48/ipAdreses/main/gemini-domains.txt`
- Remote Subnet Lists: `https://raw.githubusercontent.com/Tro48/ipAdreses/main/cidrs.txt`

Секция «ai-fr» (подключение — VLESS-ссылка французского сервера):

- Remote Domain Lists: `https://raw.githubusercontent.com/Tro48/ipAdreses/main/anthropic-domains.txt`

Общий `domains.txt` при такой схеме не подключайте.

## Использование в sing-box

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "ai-exit",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/Tro48/ipAdreses/main/singbox-ai.json",
        "download_detour": "direct"
      }
    ],
    "rules": [
      { "rule_set": "ai-exit", "outbound": "ваш-outbound" }
    ]
  }
}
```

Формат файла — source-JSON, поэтому укажите `"format": "binary"` с `"url"` (sing-box скомпилирует его сам) либо скачайте и подключите как `"type": "local", "format": "source"`.

## Автообновление

Workflow `.github/workflows/update.yml` запускается ежедневно по расписанию и вручную (Actions → Update lists → Run workflow). Учтите: GitHub отключает расписания в репозиториях без активности в течение 60 дней — в таком случае запустите обновление вручную или сделайте любой коммит.

## Предупреждение

Подключая внешние списки, вы доверяете их содержимому: список напрямую влияет на то, какие соединения роутер отправит в туннель. Подключайте только списки из источников, которым доверяете.
