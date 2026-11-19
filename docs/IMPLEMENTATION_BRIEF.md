# Бриф для кодинг-агента: No-halla — per-app kill switch для macOS

> **Как использовать.** Передай этот файл целиком кодинг-агенту в репозиторий, где уже лежит папка `design/` (результат `DESIGN_BRIEF.md`). Агент должен реализовать приложение, собрать его и прогнать тесты. Если `design/` отсутствует — реализуй UI по этому брифу и macOS HIG, а отклонения запиши в Orca pod memory (`.orca-pod/memory/`).
>
> **Роль.** Ты — senior macOS-инженер (Swift, SwiftUI, AppKit, libproc, launchd-адъяценты). Ты пишешь production-код, тесты и документацию. Ты не расширяешь scope и не добавляешь фичи, которых нет в этом документе.

---

## 0. Бренд и идентификаторы

| Сущность | Значение |
|---|---|
| Отображаемое имя | **No-halla** (всегда с заглавной N и дефисом) |
| Tagline | «Valhalla can wait.» / «Вальхалла подождёт.» |
| Метафора | VPN — ворота; trusted IP — доверенный мир; замороженные приложения ждут у ворот |
| Xcode project / scheme | `NoHalla` |
| Xcode targets | `NoHalla`, `NoHallaWatchdog`, `NoHallaCoreTests`, `NoHallaWatchdogTests` |
| App bundle | `No-halla.app` |
| `CFBundleDisplayName` / `CFBundleName` | `No-halla` |
| `PRODUCT_NAME` | `No-halla` |
| `PRODUCT_MODULE_NAME` | `NoHalla` |
| Bundle ID приложения | `dev.nohalla.NoHalla` |
| Bundle ID watchdog | `dev.nohalla.NoHallaWatchdog` |
| Watchdog binary | `No-halla.app/Contents/MacOS/NoHallaWatchdog` |
| Support dir | `~/Library/Application Support/NoHalla/` |
| OSLog subsystem | `dev.nohalla.NoHalla` |
| Menu bar image names | `MenuBarProtected`, `MenuBarGrace`, `MenuBarFrozen`, `MenuBarUnknown`, `MenuBarOff` |
| Entitlements | `NoHalla.entitlements` |
| Swift-типы входа | `NoHallaApp`, `NoHallaAppDelegate` |

Правила:

- В коде, путях и bundle ID использовать `NoHalla` без дефиса; в UI, документации и подписях — `No-halla`.
- Все UI-строки, включая скандинавские lore-подписи, брать из `design/copy.json`. Не придумывать свои метафоры в коде.
- Брендовые ассеты (иконка приложения, menu bar glyph, иллюстрации) брать из `design/exports/`; в коде не рисовать их заново.
- Скандинавская тема не меняет нативные контролы: никаких кастомных шрифтов, фонов, рамок и «металлических» текстур в UI.

---

## 1. Миссия

Реализовать **No-halla** — бесплатный open-source аналог [kordon](https://github.com/ef1m03/kordon): menu bar приложение для macOS, которое следит за внешним IP и **замораживает выбранные приложения** (`SIGSTOP`), когда IP перестаёт быть доверенным, и **возобновляет** их (`SIGCONT`), когда доверенный IP возвращается.

Ключевое отличие от системного kill switch: блокируются не все соединения, а только выбранные процессы, и не блокируются, а ставятся на паузу.

---

## 2. Границы

### In scope (v1)

- macOS 13 Ventura и новее, Apple Silicon + Intel.
- Menu bar agent (`LSUIElement`), без иконки в Dock.
- Онбординг, поповер, настройки, выбор приложений, уведомления.
- Мониторинг сети и внешнего IP, список доверенных IP/CIDR.
- Заморозка/возобновление выбранных приложений и их helper-процессов.
- Watchdog, который возобновляет приложения при аварийном завершении No-halla.
- Автозапуск при логине, локализация EN/RU, экспорт диагностики.
- Брендовые ассеты из `design/` (иконка, menu bar glyph, иллюстрации).

### Out of scope (v1)

- VPN-клиент, настройка VPN, карта серверов.
- Системный kill switch, `pf`, Network Extension, kext, системный firewall.
- Блокировка всей сети или всех приложений.
- Windows/Linux.
- Аккаунты, облако, телеметрия, аналитика, автообновление.
- Защита процессов других пользователей и root-процессов.
- App Store-дистрибуция и sandbox.

### Важное ограничение честности

`SIGSTOP` останавливает процесс, но **не является сетевым файрволом**: ядро может завершать уже установленные соединения и отправлять буферизованные данные. No-halla — это «пауза приложений» для UX-защиты от случайных запросов, а не криптографическая гарантия отсутствия утечек. Это должно быть явно написано в `README.md` и в `About`.

---

## 3. Платформа и технические ограничения

| Параметр | Решение |
|---|---|
| Минимальная ОС | macOS 13.0 |
| Архитектуры | `arm64` + `x86_64` (universal) |
| Язык | Swift 5.9+ compiler, language mode 5 (Xcode 16) |
| UI | SwiftUI + AppKit там, где нужно (`NSWorkspace`, `NSOpenPanel`, `NSSavePanel`) |
| Проект | XcodeGen (`project.yml`) → `NoHalla.xcodeproj` |
| Подпись | ad-hoc (`-`) для локальной сборки; Developer ID + notarization опционально |
| Sandbox | **выключен** (иначе нельзя посылать сигналы другим процессам и читать их пути) |
| Root | не требуется |
| kext / system extension | запрещены |
| Внешние зависимости | 0 (только системные фреймворки) |
| Данные | `~/Library/Application Support/NoHalla/` |
| Логи | `OSLog`, subsystem `dev.nohalla.NoHalla` |

---

## 4. Deliverables

Создай в корне репозитория:

```
project.yml                     # XcodeGen
NoHalla/
├── App/
│   ├── NoHallaApp.swift        # @main, MenuBarExtra, Settings, Window
│   ├── NoHallaAppDelegate.swift# lifecycle, signals, single instance
│   └── Info.plist              # LSUIElement, display name No-halla
├── Core/
│   ├── Models/
│   │   ├── AppConfig.swift
│   │   ├── ProtectedApp.swift
│   │   ├── ProtectionState.swift
│   │   ├── FrozenProcess.swift
│   │   └── TrustedAddress.swift
│   ├── Config/
│   │   ├── ConfigStore.swift
│   │   └── StateStore.swift
│   ├── Network/
│   │   ├── NetworkMonitor.swift
│   │   ├── IPVerifier.swift
│   │   └── CIDR.swift
│   ├── Process/
│   │   ├── ProcessEnumerator.swift
│   │   ├── ProcessController.swift
│   │   └── SafetyGuard.swift
│   ├── Engine/
│   │   ├── ProtectionEngine.swift
│   │   └── ProtectionStateMachine.swift
│   ├── Watchdog/
│   │   └── WatchdogLauncher.swift
│   └── Diagnostics/
│       └── DiagnosticsExporter.swift
├── UI/
│   ├── Popover/
│   ├── Onboarding/
│   ├── Settings/
│   ├── AppPicker/
│   └── Components/
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.xcstrings
│   ├── AppIcon.appiconset
│   └── MenuBarIcon.imageset    # 5 состояний
└── NoHalla.entitlements        # пустой (sandbox off)
NoHallaWatchdog/
└── main.swift                  # отдельный executable target
Tests/
├── NoHallaCoreTests/
└── NoHallaWatchdogTests/
scripts/
├── build.sh
├── test.sh
└── run.sh
README.md
LICENSE                         # MIT
.orca-pod/memory/               # отклонения и решения
```

После генерации проекта проверь, что `NoHallaWatchdog` оказался в `No-halla.app/Contents/MacOS/`; если XcodeGen разместил его иначе — добавь copy-files phase.

`README.md` должен содержать: название и tagline, что делает, чем не является, требования, сборку, запуск, автозапуск, как проверить вручную, troubleshooting (включая ручное возобновление через `kill -CONT <pid>` и Activity Monitor), удаление (включая снятие автозапуска), лицензию. Отдельно — ограничение `SIGSTOP` ≠ firewall.

---

## 5. Архитектура

### 5.1 Компоненты

| Компонент | Ответственность |
|---|---|
| `NoHallaApp` | SwiftUI-сцены: `MenuBarExtra`, `Settings`, onboarding window; связывает UI с engine |
| `NoHallaAppDelegate` | Запуск/остановка engine, watchdog, обработка `SIGTERM`/`SIGINT`, single instance, resume all при выходе |
| `NetworkMonitor` | События смены сети: `NWPathMonitor`, `SCDynamicStore`, wake, таймер; debounce 500 мс |
| `IPVerifier` | Параллельные HTTPS-запросы к endpoint'ам, кворум, таймауты, IPv4/IPv6, rate limit |
| `CIDR` | Парсинг и matching IPv4/IPv6/CIDR |
| `ProcessEnumerator` | Поиск запущенных экземпляров по bundle ID, дочерних и helper-процессов по пути внутри `.app` |
| `ProcessController` | `SIGSTOP`/`SIGCONT`, проверка pid + start time, идемпотентность, обработка `ESRCH`/`EPERM` |
| `SafetyGuard` | Список процессов, которые нельзя трогать; проверки uid, системных bundle ID |
| `ProtectionStateMachine` | Чистые переходы состояний по событиям (тестируется отдельно) |
| `ProtectionEngine` | Оркестрация: сеть → проверка IP → решение → freeze/resume → UI/уведомления |
| `ConfigStore` / `StateStore` | Атомарное JSON-хранилище, миграции, восстановление |
| `WatchdogLauncher` | Запуск/контроль `NoHallaWatchdog`, перезапуск при неожиданной смерти |
| `NoHallaWatchdog` | Следит за родителем через kqueue, при аварийном exit возобновляет PID'ы из state file |
| `DiagnosticsExporter` | ZIP с конфигом, состоянием и логами |

### 5.2 Поток данных

```
NetworkMonitor ──(event)──▶ ProtectionEngine ──▶ IPVerifier ──▶ [IPs]
                                   │
                                   ▼
                         TrustedAddress matching
                                   │
                                   ▼
                         ProtectionStateMachine
                          │                    │
                     (freeze)              (resume)
                          ▼                    ▼
                  ProcessEnumerator      ProcessController
                          │                    │
                          ▼                    ▼
                  ProcessController      StateStore.clear
                          │
                          ▼
              StateStore + UI + Notifications + Log
```

### 5.3 Состояния

```
initializing ──▶ checking ──▶ protected
                    │             │
                    │             ├──(disallowed)──▶ grace ──▶ frozen
                    │             │                            │
                    │             └──────(allowed)─────────────┘
                    │
                    └──(no quorum)──▶ unknown ──▶ grace ──▶ frozen
paused / disabled — ортогональные режимы: engine не инициирует freeze
```

Точные переходы:

| Текущее | Событие | Условие | Новое |
|---|---|---|---|
| `initializing` | app started | конфиг валиден | `checking` |
| `checking` | IP allowed | — | `protected` |
| `checking` | IP disallowed | — | `grace` |
| `checking` | no quorum | `freezeWhenUnknown == true` | `unknown` → `grace` |
| `checking` | no quorum | `freezeWhenUnknown == false` | `unknown` (без freeze) |
| `protected` | network changed | — | `checking` |
| `grace` | IP allowed | — | `protected` |
| `grace` | timer expired | — | `frozen` |
| `grace` | user tapped Freeze now | — | `frozen` |
| `frozen` | IP allowed | — | `protected` + resume |
| `frozen` | user Resume all | — | `protected` + bypass timer |
| `frozen` | user paused protection | — | `paused` + resume |
| `unknown` | IP allowed | — | `protected` |
| `unknown` | grace expired | — | `frozen` (reason unknown) |
| `paused` | pause timer expired | — | `checking` |
| `paused` | user Turn on now | — | `checking` |
| `disabled` | user enabled | — | `checking` |

**Производные UI-статусы.** `setup` (пустой trusted-список) и `bypassing` (после ручного `Resume all`) — не отдельные состояния engine, а вычисляемые представления: `setup` — при `trustedAddresses.isEmpty`, `bypassing` — подсостояние `protected` с активным таймером bypass. UI показывает их согласно дизайну, state machine остаётся прежней.

### 5.4 Конфиг

`~/Library/Application Support/NoHalla/config.json` (атомарная запись через temp + `replaceItemAt`):

```json
{
  "schemaVersion": 1,
  "onboardingCompleted": true,
  "protection": {
    "enabled": true,
    "graceSeconds": 5,
    "checkIntervalSeconds": 30,
    "freezeWhenUnknown": true,
    "checkIPv6": true,
    "requireVPNInterface": false,
    "manualResumeBypassMinutes": 5
  },
  "trustedAddresses": ["203.0.113.5", "2001:db8::/32"],
  "protectedApps": [
    { "bundleID": "com.anthropic.claudefordesktop", "name": "Claude", "enabled": true },
    { "bundleID": "com.todesktop.230313mzl4w4u92", "name": "Cursor", "enabled": true }
  ],
  "ipCheck": {
    "endpointsV4": [
      "https://api.ipify.org",
      "https://ifconfig.me/ip",
      "https://icanhazip.com",
      "https://ipinfo.io/ip"
    ],
    "endpointsV6": [
      "https://api6.ipify.org",
      "https://ifconfig.co/ip"
    ],
    "timeoutSeconds": 2.5,
    "quorum": 2
  },
  "launchAtLogin": true,
  "notifications": true,
  "language": "system"
}
```

`state.json`:

```json
{
  "schemaVersion": 1,
  "frozen": [
    {
      "pid": 12345,
      "startTimeSec": 1720000000,
      "startTimeUsec": 123456,
      "bundleID": "com.todesktop.230313mzl4w4u92",
      "path": "/Applications/Cursor.app/Contents/MacOS/Cursor"
    }
  ],
  "frozenSince": "2026-11-18T18:00:00Z",
  "reason": "ip_disallowed",
  "lastKnownIP": "198.51.100.7"
}
```

Требования:

- Запись атомарная, с `schemaVersion`, миграции при загрузке.
- Битый конфиг → значения по умолчанию, запись в лог, баннер в настройках.
- IP в логах маскировать (`203.0.113.x`), кроме явного debug-режима.

### 5.5 Watchdog

- Отдельный executable target `NoHallaWatchdog`, кладётся в `No-halla.app/Contents/MacOS/NoHallaWatchdog`.
- Запускается из `WatchdogLauncher` с аргументами: `--parent <pid> --state <path>`.
- Внутри: `kqueue` + `EVFILT_PROC`/`NOTE_EXIT` на родителя.
- При выходе родителя: подождать 1 с, прочитать `state.json`, для каждого PID проверить start time через `proc_pidinfo` (защита от переиспользования PID), послать `SIGCONT`, удалить state file.
- При штатном выходе No-halla сам возобновляет приложения и очищает state; watchdog видит пустой state и просто завершается.
- No-halla следит за watchdog: если тот умер не по команде — перезапустить и показать ошибку в логах.
- Watchdog не должен требовать root и не должен иметь UI.

---

## 6. Функциональные требования

### A. Жизненный цикл

- **FR-1.** Приложение запускается как menu bar agent (`LSUIElement = YES`), без Dock-иконки; одновременно может работать только один экземпляр (lock file + проверка `NSRunningApplication`).
- **FR-2.** Первый запуск открывает онбординг (3 шага по дизайну); после завершения `onboardingCompleted = true`.
- **FR-3.** Автозапуск через `SMAppService.mainApp.register()` / `unregister()`; статус отражается в UI; ошибки регистрации не роняют приложение, а показываются inline.
- **FR-4.** При выходе: если есть замороженные процессы — показать подтверждение из дизайна; после подтверждения послать `SIGCONT` всем, очистить state, остановить watchdog, завершиться.
- **FR-5.** `SIGTERM` и `SIGINT` обрабатываются так же, как штатный выход (resume all, очистка state).
- **FR-6.** При старте: загрузить конфиг и state; если в state есть «зависшие» frozen-записи — проверить pid+start time и послать `SIGCONT`; затем запустить watchdog и engine.

### B. Сеть и IP

- **FR-7.** Следить за изменениями сети: `NWPathMonitor`, уведомления `SCDynamicStore`, `NSWorkspace.didWakeNotification`, периодический таймер `checkIntervalSeconds` (default 30). Debounce 500 мс.
- **FR-8.** Проверять внешний IPv4 параллельно по endpoint'ам из конфига; успешный ответ — валидный IP; кворум `quorum` (default 2); таймаут 2.5 с; при включённом `checkIPv6` — аналогично IPv6.
- **FR-9.** Не запускать новый батч проверок чаще, чем раз в 3 секунды; при ошибках — backoff 5 → 60 секунд; не более 1 батча одновременно.
- **FR-10.** Поддерживать trusted-список IPv4/IPv6/CIDR; пустой список → защита неактивна, статус `setup`, предупреждение в UI.
- **FR-11.** Политика решения:
  - IP allowed → resume, `protected`;
  - IP disallowed → `grace` → freeze;
  - нет кворума (`unknown`): если `freezeWhenUnknown` — после grace freeze, иначе остаться в `unknown` и не морозить;
  - офлайн (нет сетевого пути): считать `unknown`, запросы не отправлять;
  - до первой успешной проверки после запуска — не морозить, статус `checking`.
- **FR-12.** После wake из сна — немедленная проверка, таймеры перезапускаются; во время сна никаких проверок.
- **FR-13.** Если `checkIPv6` включён и IPv6-egress существует, его IP тоже должен быть trusted; иначе IP считается недоверенным.
- **FR-14.** Если `requireVPNInterface` включён — требовать активный интерфейс `utun*`, `ipsec*`, `ppp*`, `tun*` с назначенным адресом; иначе считать IP недоверенным. По умолчанию выключено.

### C. Freeze / resume

- **FR-15.** Приложения задаются bundle ID; UI добавляет/удаляет/включает-выключает; запущенные экземпляры определяются через `NSWorkspace.runningApplications(withBundleIdentifier:)`.
- **FR-16.** Множество процессов для заморозки: основные экземпляры + дочерние (`proc_listchildpids`) + все процессы, чей `proc_pidpath` начинается с пути внутри соответствующего `.app` (helper'ы, XPC). Сканировать через `proc_listallpids` при freeze/reconcile.
- **FR-17.** Никогда не сигналить: себя, watchdog, PID 1, `kernel_task`, `WindowServer`, `Dock`, `Finder`, `loginwindow`, `SystemUIServer`, `ControlCenter`, `launchd`, процессы с uid ≠ текущего uid. Пропускать и логировать.
- **FR-18.** Freeze: `kill(pid, SIGSTOP)` каждому PID; перед сигналом проверить pid + start time (`proc_pidinfo`/`PROC_PIDTBSDINFO`); идемпотентно; `ESRCH` — удалить из трекинга, `EPERM` — пропустить и показать предупреждение в логе.
- **FR-19.** Resume: `kill(pid, SIGCONT)` с той же проверкой identity; идемпотентно; обновить UI.
- **FR-20.** Пока состояние `frozen`: слушать `NSWorkspace.didLaunchApplicationNotification` и каждые 5 с выполнять reconcile — новые экземпляры и helper'ы замораживаются в течение 2 с.
- **FR-21.** Grace: default 5 с (0–120), обратный отсчёт в UI, отмена при возврате allowed IP, кнопка `Freeze now` — немедленно.
- **FR-22.** `Resume all` вручную: возобновить все, включить bypass на `manualResumeBypassMinutes` (default 5, 0–60), по истечении — немедленная проверка и freeze, если IP всё ещё плохой.
- **FR-23.** Пауза защиты: 15 минут / 1 час / до перезапуска; при паузе возобновить всё, не инициировать freeze, по окончании — проверка. Статус с временем окончания.
- **FR-24.** Если приложение завершилось само, пока было заморожено, — убрать из state, resume не требуется.
- **FR-25.** Изменения состояния должны отражаться в UI не позднее 200 мс.

### D. UI и уведомления

- **FR-26.** Поповер, онбординг, настройки, app picker, quit dialog — строго по `design/`; 8 состояний из `DESIGN_BRIEF.md` §6.
- **FR-27.** Настройки: 4 вкладки, все поля и валидации из дизайна; `Add current IP`; редактирование endpoint'ов; сброс к дефолтам.
- **FR-28.** App picker: запущенные приложения + `/Applications`, поиск, запрет дублей, предупреждение для системных/Terminal-подобных приложений.
- **FR-29.** Локальные уведомления через `UNUserNotificationCenter`: Frozen, Resumed, Can't verify IP; action `Resume all`; учитывать toggle; не чаще 1 уведомления каждого типа за 30 с; запрашивать разрешение после онбординга.
- **FR-30.** Локализация через String Catalog (`.xcstrings`): EN базовый, RU второй; все строки из `design/copy.json`; никаких хардкод-строк.
- **FR-31.** Accessibility: VoiceOver labels для menu bar и всех статусов, клавиатурная навигация, контраст, Reduce Motion/Transparency — по `design/ACCESSIBILITY.md`.
- **FR-32.** Экспорт диагностики: ZIP (config, state, последние 15 минут логов, версия macOS, версия No-halla) через `NSSavePanel`; без автоматической отправки.

### E. Бренд и визуал

- **FR-33.** `CFBundleDisplayName` и `CFBundleName` = `No-halla`; в поповере, About, уведомлениях и README использовать `No-halla`; в коде — `NoHalla`.
- **FR-34.** Иконка приложения — из `design/exports/appicon-1024.png` (все размеры 16…1024), menu bar glyph — 5 images внутри `MenuBarIcon.imageset` из `design/exports/menubar-icons.svg` с именами из §0 и `.renderingMode(.template)`.
- **FR-35.** Брендовая палитра и иллюстрации используются только там, где указано в `design/BRAND.md`; системные контролы, статусы и кнопки остаются нативными. Никаких кастомных шрифтов, фонов и текстур.
- **FR-36.** Все lore-подписи и tagline берутся из `copy.json`; функциональные статусы (`Protected`, `Frozen`, `Resume all`) не заменяются метафорами.

### F. Конфиг, логи, приватность

- **FR-37.** Конфиг и state — в `~/Library/Application Support/NoHalla/`, атомарная запись, `schemaVersion`, миграции.
- **FR-38.** Валидация конфига при загрузке; невалидные поля → дефолты + запись в лог + баннер в настройках.
- **FR-39.** `OSLog` subsystem `dev.nohalla.NoHalla`, категории `network`, `engine`, `process`, `ui`, `watchdog`; IP маскировать, кроме debug-уровня.
- **FR-40.** Никакой телеметрии/аналитики/аккаунтов/автообновления. Единственный исходящий трафик — запросы к endpoint'ам проверки IP.

### G. Надёжность и безопасность

- **FR-41.** Watchdog из §5.5; при аварийном завершении No-halla все замороженные процессы возобновляются в течение 2 секунд.
- **FR-42.** Crash recovery: при следующем запуске stale frozen-записи возобновляются после проверки start time.
- **FR-43.** Single-instance guard: второй экземпляр завершается, активируя первый.
- **FR-44.** Сон/пробуждение: не морозить во время сна; после wake — проверка; таймеры не «догоняют» пропущенное время.
- **FR-45.** Не морозить приложение, если его bundle path не совпадает с ожидаемым (защита от подмены пути).
- **FR-46.** Все операции freeze/resume — последовательно на отдельной serial-очереди/actor, без гонок с UI.

---

## 7. Нефункциональные требования

- **NFR-1.** Idle CPU < 0.5%, RAM < 120 МБ, энергопотребление — как у фонового агента; event-driven, reconcile не чаще 1 раза в 5 с.
- **NFR-2.** Запуск приложения < 1.5 с до появления иконки в menu bar.
- **NFR-3.** Universal binary, macOS 13.0+.
- **NFR-4.** Ноль сторонних зависимостей.
- **NFR-5.** Сборка одной командой `./scripts/build.sh`; тесты — `./scripts/test.sh`.
- **NFR-6.** Core-логика покрыта unit-тестами; критические сценарии — integration-тестами.
- **NFR-7.** Нет force unwrap в production-коде; ошибки обрабатываются явно.
- **NFR-8.** Все сетевые запросы — HTTPS, таймауты, без редиректов на другие хосты (или с явной проверкой).
- **NFR-9.** Приложение корректно работает без интернета и без VPN.
- **NFR-10.** Код и документация на английском; UI-строки — EN + RU.

---

## 8. Технические заметки

### 8.1 Мониторинг сети

- `NWPathMonitor(requiredInterfaceType: .any)` — события о смене пути.
- `SCDynamicStoreCreate` + `SCDynamicStoreSetNotificationKeys` для изменений IP/маршрутов.
- `NSWorkspace.shared.notificationCenter` — `didWakeNotification`.
- Debounce: собрать события за 500 мс, затем один запуск проверки.
- Определение VPN-интерфейса: `getifaddrs`, имена `utun*`, `ipsec*`, `ppp*`, `tun*`, есть `ifa_addr`.

### 8.2 Проверка IP

- `URLSessionConfiguration.ephemeral`, `timeoutIntervalForRequest = 2.5`, `timeoutIntervalForResource = 4`.
- Параллельно через `withTaskGroup`; каждый endpoint — отдельная задача.
- Ответ: plain text IP (обрезать whitespace) или JSON с полем `ip` (поддержать оба; `ipinfo.io/ip` возвращает plain text).
- Валидация через `inet_pton(AF_INET/AF_INET6)`.
- Кворум: минимум `quorum` успешных ответов; если успешные ответы расходятся — считать `unknown` (возможен split tunnel/anycast).
- IPv6: отдельные endpoint'ы; если IPv6-egress отсутствует — не учитывать.
- Не логировать полный IP на уровне info.

### 8.3 CIDR

- Парсер IPv4/IPv6 + prefix length.
- Matching: `inet_pton` → битовая маска; для IPv6 — 128 бит.
- Поддержать одиночный IP как `/32` и `/128`.
- Валидация в UI: показывать inline-ошибку, не давать сохранить невалидное значение.

### 8.4 Управление процессами

```swift
import Darwin

func startTime(of pid: pid_t) -> (sec: Int64, usec: Int64)? {
    var info = proc_bsdinfo()
    let size = MemoryLayout<proc_bsdinfo>.stride
    let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
    guard result == Int32(size) else { return nil }
    return (Int64(info.pbi_start_tvsec), Int64(info.pbi_start_tvusec))
}

func signal(pid: pid_t, _ sig: Int32) -> Bool {
    kill(pid, sig) == 0
}
```

- Использовать константы `SIGSTOP`/`SIGCONT` из `Darwin`; не хардкодить числовые значения сигналов.
- Перечисление дочерних: `proc_listchildpids`.
- Перечисление всех: `proc_listallpids` + `proc_pidpath` (буфер `PROC_PIDPATHINFO_MAXSIZE`).
- Проверять uid: `proc_bsdinfo.pbi_uid == getuid()`.
- Перед каждым сигналом сверять start time; если не совпал — PID переиспользован, пропустить.
- Не сигналить дважды без необходимости; вести `Set<pid_t>`.

### 8.5 Безопасность

- `SafetyGuard` содержит deny-list bundle ID и executable path.
- Если пользователь добавил системное приложение — предупредить в UI; freeze всё равно пропустить, записать в лог.
- Никогда не морозить процесс, путь которого не внутри добавленного `.app` (защита от подмены).
- Не использовать приватные API. `libproc` — публичный API.
- Не включать App Sandbox; в `NoHalla.entitlements` оставить пустой словарь.
- Hardened Runtime: включить; special entitlements не нужны.
- Подпись ad-hoc достаточна для локального запуска; `SMAppService` может требовать валидную подпись — обработать ошибку и показать inline.

### 8.6 Уведомления

- Категории: `FROZEN`, `RESUMED`, `UNKNOWN`.
- Action `RESUME_ALL` с `UNNotificationAction` (foreground).
- Запрашивать permission после онбординга, не на старте.
- Если permission denied — баннер в General → открыть `x-apple.systempreferences:com.apple.Notifications-Settings.extension` (macOS 13+).

### 8.7 Автозапуск

- `SMAppService.mainApp.register()` на macOS 13+.
- Проверять `SMAppService.mainApp.status`; синхронизировать toggle с фактическим статусом.
- При ошибке — не менять конфиг молча, показать ошибку.

### 8.8 UI и бренд

- `MenuBarExtra` с `.menuBarExtraStyle(.window)`.
- Иконка: `Image("MenuBarIcon")` + `.renderingMode(.template)`; 5 состояний — 5 imageset'ов или `NSImage` с динамической заменой.
- `Settings { TabView { ... } }` с вкладками General/Protection/Advanced/About.
- Онбординг — отдельное `Window` с id, показывается, если `!onboardingCompleted`.
- Использовать токены из `design/tokens.json`; не хардкодить цвета/отступы.
- Все view — с Preview на моковых состояниях.
- Иконка приложения и брендовые иллюстрации — только из `Assets.xcassets`; не рисовать их кодом.
- Никаких кастомных шрифтов и «скандинавских» тем оформления: SF Pro, системные материалы, нативные контролы.
- Lore-подписи в поповере — из `copy.json` (ключи `status.*.lore`), 11 pt secondary; не заменяют функциональный статус.

### 8.9 Watchdog

```swift
// Упрощённо: kqueue на родителя
let kq = kqueue()
var change = kevent(
    ident: UInt(parentPID),
    filter: Int16(EVFILT_PROC),
    flags: UInt16(EV_ADD | EV_ENABLE),
    fflags: UInt32(NOTE_EXIT),
    data: 0,
    udata: nil
)
```

- После `NOTE_EXIT`: sleep 1 с, прочитать state, `SIGCONT` с проверкой start time, удалить state.
- Watchdog не должен использовать UI-фреймворки; только Foundation/Darwin.
- Если parent PID не существует на старте — сразу выйти (ничего не делать).

### 8.10 Сборка

`project.yml` (XcodeGen):

```yaml
name: NoHalla
options:
  bundleIdPrefix: dev.nohalla
  deploymentTarget:
    macOS: "13.0"
targets:
  NoHalla:
    type: application
    platform: macOS
    sources: [NoHalla]
    settings:
      base:
        PRODUCT_NAME: No-halla
        PRODUCT_MODULE_NAME: NoHalla
        PRODUCT_BUNDLE_IDENTIFIER: dev.nohalla.NoHalla
        INFOPLIST_FILE: NoHalla/App/Info.plist
        CODE_SIGN_ENTITLEMENTS: NoHalla/NoHalla.entitlements
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: "5.0"
    dependencies:
      - target: NoHallaWatchdog
        embed: true
        codeSign: true
  NoHallaWatchdog:
    type: tool
    platform: macOS
    sources: [NoHallaWatchdog]
    settings:
      base:
        PRODUCT_NAME: NoHallaWatchdog
        PRODUCT_BUNDLE_IDENTIFIER: dev.nohalla.NoHallaWatchdog
        CODE_SIGN_IDENTITY: "-"
  NoHallaCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/NoHallaCoreTests]
    dependencies:
      - target: NoHalla
  NoHallaWatchdogTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests/NoHallaWatchdogTests]
    dependencies:
      - target: NoHallaWatchdog
schemes:
  NoHalla:
    build:
      targets:
        NoHalla: all
    test:
      targets: [NoHallaCoreTests, NoHallaWatchdogTests]
```

`Info.plist`:

```xml
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleDisplayName</key><string>No-halla</string>
<key>CFBundleName</key><string>No-halla</string>
<key>CFBundleIdentifier</key><string>dev.nohalla.NoHalla</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
```

Скрипты:

```bash
# scripts/build.sh
xcodegen generate
xcodebuild -project NoHalla.xcodeproj -scheme NoHalla -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" build

# scripts/test.sh
xcodegen generate
xcodebuild -project NoHalla.xcodeproj -scheme NoHalla \
  -derivedDataPath build test
```

---

## 9. Тестовая стратегия

### Unit-тесты (обязательны)

- `CIDR`: IPv4/IPv6, границы, невалидные значения, `/0`, `/32`, `/128`.
- `ProtectionStateMachine`: все переходы из §5.3, включая unknown/paused/bypass.
- `IPVerifier`: кворум, расхождение ответов, таймауты, backoff, IPv6-off (mock URLProtocol).
- `ConfigStore`: кодирование/декодирование, миграции, битый JSON, атомарная запись.
- `SafetyGuard`: deny-list, uid, path-prefix.
- `ProcessController`: identity-check, идемпотентность, ESRCH/EPERM (на тестовом процессе).
- `TrustedAddress`: маскирование в логах.

### Integration-тесты

- Запустить `sleep 300` как тестовый «защищённый процесс», заморозить, проверить `ps -o state= -p <pid>` = `T`, возобновить — процесс жив.
- Watchdog: запустить No-halla, заморозить `sleep`, убить No-halla `SIGKILL`, убедиться, что `sleep` возобновился.
- Crash recovery: записать state с живым PID, запустить приложение, убедиться в `SIGCONT`.

### Ручная матрица (обязательно прогнать и отметить в README/PR)

| # | Сценарий | Ожидание |
|---|---|---|
| 1 | VPN включён, IP доверенный | `Protected`, приложения активны |
| 2 | Отключить VPN, IP изменился | `Grace` → `Frozen`, `ps` показывает `T` |
| 3 | Вернуть VPN | `Protected`, приложения возобновлены |
| 4 | Запустить новый экземпляр при `Frozen` | Заморожен в течение 2 с |
| 5 | Quit при заморозке | Подтверждение, после — resume all |
| 6 | `kill -9` No-halla при заморозке | Watchdog возобновляет приложения |
| 7 | Сон/пробуждение | Проверка после wake, без ложной заморозки |
| 8 | Wi-Fi → Ethernet, IP тот же | Без заморозки |
| 9 | Все endpoint'ы недоступны | `Unknown`, после grace — заморозка (по умолчанию) |
| 10 | `Add current IP` при заморозке | Приложения возобновляются |
| 11 | Пауза 1 час | Заморозки нет, статус с временем |
| 12 | `Resume all` при плохом IP | Bypass 5 минут, затем снова заморозка |
| 13 | IPv6 leak (если включён) | IP считается недоверенным |
| 14 | Запуск без admin | Работает без root |
| 15 | Cursor/Claude с helper'ами | Helper-процессы тоже `T` |
| 16 | Удалить приложение из списка при заморозке | Процесс возобновляется |
| 17 | Сменить конфиг вручную на битый | Дефолты, баннер, приложение работает |
| 18 | About | Показаны No-halla, tagline «Valhalla can wait.», версия, MIT |
| 19 | Menu bar | 5 состояний различимы, template-рендеринг в light/dark |
| 20 | Смена языка EN/RU | Все строки, включая lore, переключаются без обрезки |

### Definition of Done

- [ ] `./scripts/build.sh` проходит без ошибок.
- [ ] `./scripts/test.sh` зелёный.
- [ ] Все FR-1…FR-46 реализованы или явно отмечены как отложенные в Orca pod memory (не больше 3).
- [ ] Ручная матрица 20/20 пройдена.
- [ ] UI соответствует `design/HANDOFF.md`; отклонения согласованы и записаны.
- [ ] EN/RU строки на месте, нет хардкода.
- [ ] Иконка приложения и 5 состояний menu bar установлены; отображаемое имя No-halla.
- [ ] README с ограничениями (`SIGSTOP` ≠ firewall), сборкой, запуском, удалением.
- [ ] Нет телеметрии, нет сетевых запросов кроме IP-endpoint'ов.
- [ ] Watchdog протестирован.
- [ ] Приложение не требует root и не трогает системные процессы.

---

## 10. Milestones

| Этап | Содержание | Критерий готовности |
|---|---|---|
| M1 | Scaffold: XcodeGen, menu bar, конфиг, токены дизайна | `No-halla.app` запускается, иконка в menu bar, конфиг сохраняется |
| M2 | NetworkMonitor + IPVerifier + CIDR + state machine | Unit-тесты ядра зелёные, статус в UI меняется на моках |
| M3 | ProcessEnumerator + ProcessController + freeze/resume + SafetyGuard | `sleep`-тест замораживается/возобновляется, safety-тесты зелёные |
| M4 | Watchdog + crash recovery + single instance + quit flow | `kill -9` возобновляет процессы |
| M5 | UI по дизайну: поповер, онбординг, настройки, app picker, уведомления, локализация | Все экраны из `design/mockups` реализованы |
| M6 | Бренд-ассеты, диагностика, README, LICENSE, финальная матрица тестов | Definition of Done выполнен |

---

## 11. Риски и mitigation

| Риск | Mitigation |
|---|---|
| IP-check endpoints недоступны (в т.ч. в РФ) | Настраиваемый список endpoint'ов, backoff, статус `unknown`, возможность resume all; в README — как добавить свой endpoint |
| Ложная заморозка при переподключении VPN | Grace 5 с, debounce 500 мс, trusted CIDR, bypass после ручного resume |
| `SIGSTOP` не блокирует уже открытые сокеты | Явно задокументировать ограничение; не обещать «zero leak»; для строгой защиты рекомендовать системный firewall |
| PID reuse | Проверка start time перед каждым сигналом |
| Зависшие процессы после краха No-halla | Watchdog + crash recovery + resume на старте |
| Helper-процессы остаются активными | Сканирование по path-prefix внутри `.app`, reconcile каждые 5 с |
| Root-процессы/другие пользователи | Пропускать, логировать, не обещать защиту |
| `SMAppService` не работает на ad-hoc сборке | Обработать ошибку, показать inline, не ломать приложение |
| `kill` заблокирован для некоторых процессов | `EPERM` — пропустить, предупредить в логе, не падать |
| Утечка IP в логи | Маскирование, debug-only полный IP |
| Сон/пробуждение ломает таймеры | Пересоздавать таймеры после wake, проверка сразу |
| Скандинавская тема ухудшает ясность | Функциональные подписи обязательны, lore — только вторичная строка; ревью по `BRAND.md` |
| Китч в ассетах | Чеклист запретов из дизайн-брифа, ревью иконки на 16 px |

---

## 12. Правила для агента

1. Сначала прочитай `DESIGN_BRIEF.md`, `design/BRAND.md` и `design/HANDOFF.md`; UI реализуй по макетам, токенам и ассетам.
2. Конфликты: поведение — этот документ, пиксели/тексты/бренд — дизайн.
3. Не добавляй фичи вне scope (история IP, графики, VPN-подключение, системный firewall, Windows/Linux).
4. Не используй сторонние зависимости.
5. Пиши unit-тесты до/вместе с core-логикой; UI — с Preview.
6. Все отклонения и неоднозначные решения — в Orca pod memory с обоснованием.
7. Держи код простым: без преждевременных абстракций, без «на будущее».
8. Коммиты — логическими блоками; сообщения по существу.
9. Не оставляй `TODO` в critical path (freeze/resume/watchdog).
10. Работай автономно; если чего-то не хватает — выбери разумный дефолт из этого документа и зафиксируй его.
11. Не переименовывай продукт обратно в Halt и не используй старые идентификаторы `dev.halt.*`, `Halt.app`, `HaltWatchdog`.

---

## 13. Приложение: дефолты

| Параметр | Значение |
|---|---|
| Grace period | 5 с |
| Check interval | 30 с |
| Freeze when unknown | on |
| Check IPv6 | on |
| Require VPN interface | off |
| Manual resume bypass | 5 мин |
| Quorum | 2 |
| Timeout | 2.5 с |
| Notifications | on |
| Launch at login | on |
| Язык | system (EN/RU) |
| Логи | info, IP маскируется |

Рекомендуемые bundle ID для онбординга (проверять фактическое наличие через `NSWorkspace`, не хардкодить как истину):

- Claude Desktop: `com.anthropic.claudefordesktop`
- Cursor: `com.todesktop.230313mzl4w4u92`
- ChatGPT: `com.openai.chat`

---

## 14. Чеклист самопроверки перед сдачей

- [ ] `xcodegen generate && xcodebuild build` проходит.
- [ ] Юнит- и integration-тесты зелёные.
- [ ] `sleep`-сценарий: `T` → `S` (или `R`/`S`) после resume.
- [ ] `kill -9` No-halla → процессы возобновлены watchdog'ом.
- [ ] Все 8 состояний UI достижимы и соответствуют дизайну.
- [ ] Онбординг, настройки, app picker, quit dialog работают.
- [ ] Уведомления и action `Resume all` работают.
- [ ] Автозапуск включается/выключается, ошибки видны.
- [ ] EN/RU переключение работает, lore-подписи не обрезаются.
- [ ] `CFBundleDisplayName` = No-halla; иконка приложения и 5 состояний menu bar на месте.
- [ ] Нет сетевых запросов, кроме IP-endpoint'ов (проверить в Little Snitch/LuLu или `nettop`).
- [ ] README описывает ограничения и удаление.
- [ ] `LICENSE` MIT на месте.
- [ ] В репозитории не осталось идентификаторов `Halt`, `dev.halt`, `HaltWatchdog`.