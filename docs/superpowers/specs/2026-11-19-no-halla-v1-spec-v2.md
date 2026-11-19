# Спецификация: No-halla v1 — реализация приложения целиком (M1–M6)

Дата: 2026-11-19 · Статус: на утверждении (ревизия C2) · Версия: spec-v2 — ревизия spec-v1@1 по PLAN_REVISION_REQUIRED (C2: конфликт гарантий восстановления G1/G2). Утверждённая версия неизменяема. Предыдущая: `2026-11-19-no-halla-v1-spec.md` (spec-v1@1, действует во всём, кроме изменённых пунктов).
Роль: Planner, orca-pod run e1363f11-b45a-4142-aa18-a90b785c5f8a · Профиль: ChainaPower · LANGUAGE: ru

## 1. Источники истины

| Источник | Роль |
|---|---|
| `docs/IMPLEMENTATION_BRIEF.md` | Поведение, архитектура, FR-1…FR-46, NFR, дефолты (§13), границы (§2) |
| `docs/DESIGN_BRIEF.md` + `design/` | Пиксели, тексты, бренд, состояния UI, доступность |
| Doop-канвас `http://localhost:4300/c/2lgrE5QsCb` | Визуальный источник истины; доступен через doop MCP (`doop_get_canvas` / `doop_get_frame` / `doop_get_frame_screenshot`) |
| `design/HANDOFF.md` | Маппинг экран → Doop frame id → офлайн-макет → SwiftUI view → FR |
| `design/tokens.json`, `design/copy.json` | Токены (light/dark/contrast) и все строки EN/RU |
| `design/BRAND.md`, `design/ICONS.md`, `design/COMPONENTS.md`, `design/ACCESSIBILITY.md` | Бренд-правила, имена ассетов, компоненты, доступность |
| `AGENTS.md`, Orca pod memory | Правила проекта и уже принятые владельцем решения |

Правило конфликтов (бриф §12): поведение — IMPLEMENTATION_BRIEF; пиксели/тексты/бренд — дизайн. Отклонения фиксируются в Orca pod memory.

## 2. Интент и зачем

Реализовать с нуля **No-halla** — бесплатный open-source menu bar агент для macOS 13+: следит за внешним IP и ставит выбранные приложения на паузу (`SIGSTOP`), когда IP перестаёт быть доверенным, и возобновляет (`SIGCONT`) при возврате доверенного IP. Это «пауза приложений» для UX-защиты от случайных запросов, **не сетевой файрвол**: ядро может завершать уже установленные соединения и отправлять буферизованные данные. Ограничение честно документируется в README и About (бриф §2, FR-33…36).

Репозиторий сейчас содержит только документы и дизайн; кода нет. Владелец выбрал **полный v1 за один запуск** (все шесть майлстоунов брифа §10), тремя стадиями с ревью после каждой.

## 3. Цели / не-цели / анти-цели

**Цели:** рабочее приложение по брифу и дизайну: онбординг, поповер, настройки, app picker, уведомления, мониторинг сети/IP, freeze/resume с safety-правилами, watchdog и crash recovery, автозапуск, EN/RU, экспорт диагностики, бренд-ассеты, README/LICENSE. Сборка одной командой `./scripts/build.sh`, universal (arm64+x86_64), ad-hoc подпись, Hardened Runtime, без sandbox и root.

**Не-цели (v1, бриф §2):** VPN-клиент, системный kill switch/pf/Network Extension/kext, блокировка всей сети, Windows/Linux, аккаунты/облако/телеметрия/автообновление, защита чужих и root-процессов, App Store/sandbox.

**Анти-цели:** обещание «zero leak»; заморозка системных процессов; скандинавский китч в UI (рога/руны вместо текста/металлические текстуры); кастомные шрифты и веб-вид контролов; фичи вне брифа (история IP, графики, статистика); `TODO`-заглушки в critical path (freeze/resume/watchdog); идентификаторы `Halt`/`dev.halt.*`.

## 4. Ограничения

macOS 13.0+ · Swift 5.9+ compiler, language mode 5 · SwiftUI + AppKit где нужно · только системные фреймворки, 0 зависимостей · XcodeGen (`project.yml` → `NoHalla.xcodeproj`, scheme `NoHalla`) · sandbox off, Hardened Runtime on, ad-hoc (`-`) · без root, без приватных API (`libproc` — публичный) · данные в `~/Library/Application Support/NoHalla/` · `OSLog` subsystem `dev.nohalla.NoHalla`, категории network/engine/process/ui/watchdog, IP маскируется вне debug · исходящий трафик — только настроенные HTTPS IP-endpoint'ы · код и документация на английском, UI-строки EN+RU из `copy.json` · `No-halla` в UI/доках, `NoHalla` в коде; bundle ID `dev.nohalla.NoHalla` и `dev.nohalla.NoHallaWatchdog`; watchdog встроен в `No-halla.app/Contents/MacOS/NoHallaWatchdog` · без force unwrap в production (NFR-7) · UI-обновление ≤200 мс, countdown ±100 мс (бриф FR-25, дизайн §8).

## 5. Подходы и выбор

Архитектура предписана брифом §5 и `AGENTS.md`; альтернативы, которые я рассматривал и почему они не подходят:

1. **AppKit-only UI** — отвергнуто: бриф и HANDOFF требуют SwiftUI-сцены (`MenuBarExtra`, `Settings`, `Window`) с AppKit-мостами; дизайн маппится на SwiftUI views.
2. **SPM-executable вместо XcodeGen/.app** — отвергнуто: нужен полноценный `.app` bundle со встроенным watchdog, Info.plist (`LSUIElement`), ассет-каталогом и String Catalog; бриф §8.10 задаёт XcodeGen.
3. **Системный kill switch (pf/NE)** — вне scope брифа §2; продукт принципиально про паузу выбранных процессов.
4. **Сторонние библиотеки** — запрещены (NFR-4).

**Выбрано:** архитектура брифа §5 как есть, поставка тремя стадиями (D5). Внутри модулей детали реализации — на усмотрение строителя (раздел 12).

## 6. Реестр решений

Статусы: `user-approved` — решено владельцем; `author-proposed` — моё решение, показывается при утверждении; `open-fork` — вилка для блица.

### Принято владельцем

| ID | Решение | Источник |
|---|---|---|
| D1 | Полный v1 (M1–M6) за один запуск, три стадии с ревью после каждой | Окно объёма, 2026-11-19 (Planner) |
| D2 | **Тесты исключены**: не писать, не менять, не запускать тесты, без TDD. Проверки статические | Решение владельца, передано Coordinator; `tests: not requested` |
| D3 | Dark-first нативная бренд-оболочка (фьорд/бронза), следует системной теме; бронза — только декор, не текст/смысл/primary | Orca pod memory 2026-11-19 (owner-approved), дизайн §10 |
| D4 | Дизайн-источник: Doop-канвас + `design/HANDOFF.md`; офлайн-макеты — fallback | Задача, HANDOFF |
| D29 | **Восстановление после аварии — identity-checked intent recovery (приоритет G1, буквальный FR-42).** Запись-интент до SIGSTOP; startup и watchdog возобновляют identity-matched записи (pid+start time). G2 («не снимать чужую паузу») ослаблен в узком окне аварии: интент записан, SIGSTOP не прошёл/авария до подтверждения, процесс независимо остановлен другим агентом внутри защищённого bundle. Остаточный риск **принят владельцем**; документируется в Orca pod memory и README. Варианты B (confirmed-stop журнал, дыра FR-41) и C (эвристика SSTOP/P_TRACED) отклонены. Перенос записи после SIGSTOP и игнорирование pending запрещены (ломают G1). | Блиц ревизии C2, 2026-11-19 (ответ «Полное восстановление»); `.orca-pod/reports/plan-v1/C2-guarantee-conflict.md`, `chief-attempt4.md` |

### Предложено автором (показывается при утверждении)

| ID | Решение | Обоснование/цена |
|---|---|---|
| D5 | Стадии: S1 = M1+M2 (каркас+ядро), S2 = M3+M4 (процессы+надёжность), S3 = M5+M6 (UI+бренд+доки) | Реализует D1; ошибки ядра дороги, поэтому ранние ревью-чекпойнты |
| D6 | Verification: `xcodegen generate` + `xcodebuild -scheme NoHalla -configuration Release build` (компиляция/типизация) на каждой стадии; кумулятивно на финальной. Приложение пайплайном **не запускается**; первый запуск и ручная матрица 20 сценариев — чеклист для владельца в README | Соблюдает «проверки статические» и не трогает машину владельца (login items, заморозка реальных приложений). Цена: runtime-доказательство запуска — за владельцем |
| D7 | Конкурентность: `ProtectionEngine` — actor; freeze/resume последовательно (FR-46); UI-мост — `@MainActor ObservableObject` (`AppState`); `ProtectionStateMachine` — чистая структура без I/O | Бриф FR-46 допускает serial queue/actor; actor + MainActor-мост проще и безопаснее в SwiftUI |
| D8 | Шов `ProcessControlling` (протокол) в S1; реальная реализация в S2. В S1 engine публикует статусы, freeze/resume-интенты уходят в протокол | Стадийность без заглушек в финальном коде |
| D9 | Ассеты: AppIcon — `sips` из `design/exports/appicon-1024.png` (все размеры macOS); menu bar — python3-скрипт (stdlib) разрезает `menubar-icons.svg` на 5 отдельных SVG (viewBox 18×18) → imageset'ы `MenuBarProtected/Grace/Frozen/Unknown/Off` с `preserves-vector-representation` и template-рендерингом; GateRule/GateScene — SVG-ассеты из геометрии `brand-sheet.svg` | Только системные инструменты; SVG в asset catalog поддерживается Xcode 12+. Fallback при проблемах рендеринга: растеризация `qlmanage` |
| D10 | `Localizable.xcstrings` генерируется скриптом `scripts/gen-strings.py` из `design/copy.json` (EN база + RU), результат в репозитории; ключи = dotted-ключи copy.json; хардкод строк запрещён (FR-30) | Воспроизводимо, без ручного переноса ~150 строк |
| D11 | В конфиг добавляется `logLevel: "info" \| "debug"` (default info) — дизайн требует Advanced → Log level; расширение схемы брифа §5.4, фиксируется в Orca pod memory | Дизайн требует поле; бриф его не описывает — минимальное расширение |
| D12 | Язык: выбор System/English/Русский сохраняется; применение — кнопка «Apply language change» (ключ copy.json) **без перезапуска**: строки читаются через localization-хелпер из bundle выбранного языка (en.lproj/ru.lproj) внутри процесса; смена языка немедленно перерисовывает UI. Системные панели (NSOpenPanel/NSSavePanel) остаются на системном языке | Перезапуск конфликтовал бы с FR-4/FR-5 (resume all при выходе) и single-instance lock; in-process переключение безопасно и не снимает заморозку. Цена: все строки идут через хелпер |
| D13 | `NotificationCoordinator` живёт в `NoHalla/Core/Notifications/` (дополнение к layout брифа §4), категории FROZEN/RESUMED/UNKNOWN, action RESUME_ALL, throttle 30 с на тип, permission после онбординга, баннер при отказе | Сервис, не UI; место фиксируется заранее |
| D14 | Диагностика: ZIP через системный `/usr/bin/zip`; логи последних 15 минут — `OSLogStore` (current process); config+state+версии; `NSSavePanel`, без отправки (FR-32) | Foundation не умеет ZIP; системный zip — без зависимостей |
| D15 | Single instance: `flock` lock-file в support dir + проверка `NSRunningApplication`; второй экземпляр активирует первый и завершается (FR-1, FR-43) | Бриф §6A |
| D16 | Создаётся `.gitignore`: `build/`, `DerivedData/`, `.DS_Store`, `NoHalla.xcodeproj` (генерируется), `.orca-pod/` | В репозитории нет .gitignore; generated-проект не коммитится |
| D17 | XcodeGen ставится через Homebrew (`/opt/homebrew/bin/brew` присутствует); контроль `xcodegen --version` | Бриф требует XcodeGen; в окружении его нет |
| D18 | В S1 минимальный UI: `MenuBarExtra` + placeholder-поповер с живым статусом engine; полные экраны — S3 | M1 критерий «приложение собирается и запускаемо» без двойной работы |
| D19 | Check interval: диапазон 10–120 с, default 30 (дизайн §7.4; бриф задаёт только default) | Дизайн уточняет диапазон |
| D20 | Quit-подтверждение — только если есть замороженные; нативный alert со строками `quit.*` (Cancel / Quit and Resume); после подтверждения resume all + очистка state + остановка watchdog (FR-4) | Дизайн §7.7 |
| D21 | About: версия 0.9.0, tagline, MIT; `LICENSE` MIT; README по брифу §4 (включая `SIGSTOP ≠ firewall`, troubleshooting с `kill -CONT`, удаление, снятие автозапуска) + чеклист ручной матрицы | Бриф §4, FR-33 |
| D22 | `copy.json` расширяется **аддитивно**: новые ключи EN+RU для отсутствующих строк (баннер битого конфига FR-38, подписи Log level Info/Debug, единицы s/min, переключатель «Защита» (D27)) и параметризация мок-литералов (`caption.resumeBypass` «5 minutes» → `%d`, `ui.checking-resumes-at-14-32` → `%@`, `ui.2-apps-selected` → `%d`, `ui.version-0-1-0` → `%@`); каталог перегенерируется (D10); расширение и новые тексты в тоне дизайн §9 фиксируются в Orca pod memory | FR-30 запрещает хардкод, но часть обязательных строк в copy.json отсутствует; единственный совместимый путь — расширить источник. Цена: новые EN/RU тексты пишем мы в тоне дизайна |
| D23 | `MenuBarExtra(.window)` сохраняется (мандат брифа §8.8 и дизайн §7.2; альтернатива NSStatusItem+NSPopover ruled out). Esc-закрытие поповера — best-effort в рамках MenuBarExtra (закрытие key window / скрытый шорткат); если на macOS 13 недостижимо — a11y-пробел документируется в Orca pod memory и README (в счёт ≤3 отклонений) | Архитектура UI предписана; клавиатурное требование дизайна выполняется насколько позволяет платформа, пробел не замалчивается |

### Вилки, закрытые блицем (раунд 1, 2026-11-19) — решения владельца

| ID | Решение (ответ владельца) | Источник |
|---|---|---|
| D24 (F1) | Grace period: **0–120 с** везде (конфиг и слайдер), default 5; отклонение от макета (0–60) записать в Orca pod memory | Блиц, пункт 1 |
| D25 (F2) | «Cancel» во время grace: **немедленная перепроверка** → `checking`; если IP всё ещё недоверенный — countdown начинается заново; скрытого bypass нет | Блиц, пункт 2 |
| D26 (F3) | About: **строка Repository скрыта**, пока не появится реальный URL; отклонение записать; ключ `ui.repository` пока не используется | Блиц, пункт 3 |
| D27 (F4) | **Переключатель «Защита» в начале вкладки Protection**: выключение → resume all + `protection.enabled=false` → `disabled`; включение → `checking`; новые строки EN/RU (D22); отклонение от макетов записать | Блиц, пункт 4 |
| D28 (F5) | Непроверяемый IPv6 (egress есть, кворума нет) → **unknown** (FR-11 governs); известный недоверенный IPv6 → disallowed (FR-13); решётка композиции ниже | Блиц, пункт 5 |

## 7. Поведение (по брифу; ключевые инварианты)

Полный текст FR-1…FR-46 — в `docs/IMPLEMENTATION_BRIEF.md` §6; он нормативен. Критические инварианты, которые план обязан покрыть:

- **Состояния (§5.3):** initializing → checking → protected/grace/unknown; grace → frozen (timer/Freeze now); frozen → protected (allowed IP / Resume all + bypass); paused/disabled ортогональны; `setup` (пустой trusted-список) и `bypassing` — производные UI-статусы, не состояния engine. Таблица переходов брифа §5.3 — единственная истина для `ProtectionStateMachine`.
- **Решение IP (FR-11…14):** allowed → resume/protected; disallowed → grace → freeze; no quorum → unknown (+freeze после grace, если `freezeWhenUnknown`); офлайн → unknown без запросов; до первой успешной проверки не морозить; IPv6-egress при включённом `checkIPv6` тоже должен быть trusted; `requireVPNInterface` (default off) требует активный `utun*/ipsec*/ppp*/tun*` с адресом.
- **Решётка композиции IPv4/IPv6 (уточнение FR-8/11/13):** кворум считается отдельно по каждому семейству; результат = любой disallowed → disallowed; иначе любой unknown → unknown; иначе allowed. Known недоверенный IPv6 → disallowed. Непроверяемый IPv6 (egress есть, кворума нет) → unknown (D28). `requireVPNInterface` без активного туннеля → disallowed.
- **Проверка (FR-8/9, §8.2):** параллельные HTTPS-запросы (ephemeral URLSession, task group), timeout 2.5 с (resource 4 с), quorum 2, расхождение ответов → unknown, plain-text или JSON `ip`, валидация `inet_pton`, батч не чаще 3 с, backoff 5→60 с, не более 1 батча.
- **Сеть (FR-7/12, §8.1):** NWPathMonitor + SCDynamicStore + wake + таймер 30 с, debounce 500 мс; после wake немедленная проверка, таймеры пересоздаются, во сне проверок нет.
- **Freeze/resume (FR-15…24, §8.4):** множество = основные экземпляры + дети (`proc_listchildpids`) + процессы с `proc_pidpath` внутри `.app`; перед каждым сигналом pid+start time (`proc_pidinfo`/`PROC_PIDTBSDINFO`); идемпотентность (`Set<pid_t>`); ESRCH → убрать из трекинга, EPERM → пропуск+лог; deny-list (себя, watchdog, PID 1, kernel_task, WindowServer, Dock, Finder, loginwindow, SystemUIServer, ControlCenter, launchd, uid ≠ текущего) — пропуск+лог; путь вне добавленного `.app` не сигналить (FR-45); reconcile каждые 5 с + didLaunchNotification, новые экземпляры заморожены ≤2 с; grace default 5 с с countdown и Freeze now; Resume all → bypass 5 мин (0–60), затем немедленная проверка; пауза 15 мин/1 ч/до перезапуска с resume и временем окончания; завершившееся приложение убрать из state.
- **Надёжность (FR-4…6, FR-41…44, §5.5):** quit/SIGTERM/SIGINT → resume all + очистка state + остановка watchdog; старт → recovery stale frozen-записей (pid+start time → SIGCONT); watchdog `--parent <pid> --state <path>`, kqueue EVFILT_PROC/NOTE_EXIT, пауза 1 с, проверка start time, SIGCONT, удаление state; штатный выход — пустой state, watchdog просто завершается; нештатная смерть watchdog → перезапуск + лог; крах No-halla → возобновление ≤2 с. **Семантика восстановления закреплена D29:** pre-write intent + identity-checked recovery (G1 полностью, включая аварию после успешного SIGSTOP до подтверждения); ограничение владения в узком окне аварии принято владельцем и документируется; вне этого окна экспозиция G2 сужена SafetyGuard (только процессы внутри выбранного `.app`, текущий пользователь, не deny-list).
- **Конфиг (§5.4):** атомарная запись temp+replace, `schemaVersion`, миграции, битый конфиг → дефолты+лог+баннер в настройках; дефолты — бриф §13; `logLevel` добавлен (D11).
- **Уведомления (FR-29, §8.6):**permission после онбординга; отказ → inline-баннер General с открытием системных настроек уведомлений.
- **Автозапуск (FR-3, §8.7):** `SMAppService.mainApp` register/unregister/status; ошибка — inline, не молча, приложение не ронять (ad-hoc подпись может мешать).
- **Приватность (FR-39/40):** IP маскировать (`203.0.113.x`) вне debug; никакой телеметрии.

## 8. UI и бренд (по дизайну)

Экраны и маппинг — `design/HANDOFF.md` (79 frame-ссылок; Dark — первичный референс, Light — адаптация, обе темы + Increase Contrast). Компоненты — `design/COMPONENTS.md`: Button (native styles, blue Resume all, destructive только Reset, target ≥28 pt), GateRule (1 pt бронза, 24 штриха, скрыт от accessibility), GateScene (hero/About/empty vignette, декор), Protection badge (глиф+семантический текст+бронзовый ободок), Network field (mono IP, refresh), App row (44 pt, иконка 20 pt, toggle, frozen rim), Search field, Picker row (warning для системных), Settings toolbar (4 вкладки, бронзовое подчёркивание), Setting row, Sheet/alert (системные), Countdown (линейный бар+текст; Reduce Motion — snap).

- **Поповер 360 pt** (`PopoverView`): header No-halla + статус-пилюля + lore 11 pt (фиксированная высота, не прыгает); бронзовая линия ворот; network card (Current IP mono / VPN interface / Trusted, Add current IP если не доверенный, при unknown — `—`); Protected apps (строки Active/Frozen/Not running + toggle, empty state «No one is guarding the gate yet» + Choose apps); primary action по состоянию (protected→Pause меню 15/60/until relaunch; grace→Freeze now + Cancel (немедленная перепроверка, D25) + countdown; frozen→Resume all + caption bypass; unknown→Retry + Resume all; paused→Turn on now + время; setup→Add current IP); footer Settings/Quit. Без скролла при 0–4 приложениях, дальше — скролл только списка. Все 8 состояний + bypassing/empty/offline/first-run варианты из HANDOFF.
- **Онбординг 560×420, ровно 3 шага** (`OnboardingIntroView`, `OnboardingAppsView`, `OnboardingTrustedRealmView`): hero-иллюстрация ворот/фьорда (SF Pro Display 22–24 pt), Continue/Skip; выбор запущенных приложений с поиском, предложения Claude/Cursor/ChatGPT только если запущены (проверка NSWorkspace), Add other app… → NSOpenPanel, счётчик; текущий IP крупно, Trust this IP / Add manually с валидацией, toggle Launch at login (default on), Finish → системный запрос уведомлений.
- **Настройки 680×520, 4 вкладки** (`SettingsGeneralView`, `SettingsProtectionView`, `SettingsAdvancedView`, `SettingsAboutView`): поля и валидации по дизайн §7.4 (см. D11/D12/D19/D24/D26/D27): master-переключатель «Защита» в начале Protection (D27), Grace period slider 0–120 с (D24); Trusted IPs add/remove/edit + Add current IP; Protected apps add/remove; endpoints v4/v6 edit/reset (валидация HTTPS); Reset all settings — destructive с подтверждением (`ResetSettingsAlert`); Export diagnostics; About — иконка, tagline, версия, MIT, Copy version info, орнамент, строка Repository скрыта (D26).
- **App picker 480×520** (`AppPickerSheet`): Running + /Applications, поиск по имени и bundle ID, Added-disabled, жёлтое предупреждение системным/Terminal-подобным, Cancel/Add (disabled без выбора), `Add other app` через NSOpenPanel.
- **Menu bar:** 5 template-глифов 18 pt (имена §0 брифа, маппинг ICONS.md), смена вместе со статусом без задержки; VoiceOver-лейблы по ACCESSIBILITY.md («No-halla, protected» и т.д.).
- **Доступность (FR-31, ACCESSIBILITY.md):** статус читается до lore; вежливые анонсы значимых смен (не каждого тика); фокус-порядок header→network→apps→action→footer; Esc закрывает поповер/шит/меню Pause, возврат фокуса; контраст ≥4.5:1 текст / ≥3:1 нетекст; Increase Contrast — контрастные границы; Reduce Transparency — opaque fallback; Reduce Motion — без опциональных переходов; RU-строки не обрезаются на 360 pt (эталон — grace frame RU).
- **Бренд (FR-33…36, BRAND.md, дизайн §13):** ассеты только из `design/exports/`; бронза не для текста/смысла/primary; lore не заменяет функциональные подписи и не идёт в уведомления вместо причины; без эмодзи, звуков, китча; нативные контролы и SF Pro.
- **Previews:** каждая SwiftUI view — с Preview на моковых состояниях (бриф §8.8).

## 9. Данные

`config.json` и `state.json` — схемы брифа §5.4 (+ `logLevel`, D11), атомарная запись, schemaVersion=1, миграции при загрузке, битый конфиг → дефолты+лог+баннер. `state.json.frozen[]`: pid, startTimeSec/Usec, bundleID, path; frozenSince, reason (`ip_disallowed`/`unknown`/…), lastKnownIP (маскируется в логах). Поддержка одиночного IP как /32 и /128; CIDR IPv4/IPv6 битовыми масками (§8.3).

## 10. Стадии и майлстоуны

| Стадия | Майлстоуны | Содержание | Критерий готовности стадии (адаптирован под D2/D6) |
|---|---|---|---|
| S1 | M1+M2 | Scaffold (project.yml, Info.plist, entitlements, scripts, ассеты, токены, строки), модели+хранилища, CIDR, NetworkMonitor, IPVerifier, ProtectionStateMachine, ProtectionEngine (шов D8), минимальный menu bar UI | Сборка зелёная; `.app` собирается, watchdog-target объявлен; конфиг сохраняется (код-ревью); статусы engine меняются на моках; ядро без I/O в state machine |
| S2 | M3+M4 | ProcessEnumerator, SafetyGuard, ProcessController, wiring engine↔process (reconcile, grace/bypass/pause таймеры), Watchdog+Launcher, lifecycle (quit/SIGTERM/SIGINT/single instance/startup recovery), NotificationCoordinator | Сборка зелёная; freeze/resume/watchdog/recovery реализованы по FR; safety-правила на месте; последовательность операций (FR-46) |
| S3 | M5+M6 | Все экраны по HANDOFF (поповер/онбординг/настройки/picker/alerts), компоненты, локализация EN/RU, бренд-ассеты установлены, диагностика, README/LICENSE/DECISIONS, accessibility-проход, Previews | Сборка зелёная (кумулятивно); все экраны/состояния реализованы; строки без хардкода; ассеты на месте; документация полная |

Финальный вердикт: Reviewer принимает стадии (≤3 попытки), Chief Reviewer выдаёт `FINAL_APPROVED` (≤2 попытки). Режим `full`.

## 11. Приёмка (адаптированный Definition of Done)

С учётом D2 (тесты исключены владельцем) и D6 (статические проверки):

1. `./scripts/build.sh` проходит без ошибок (xcodegen + xcodebuild Release, universal, ad-hoc).
2. `NoHallaWatchdog` находится в `No-halla.app/Contents/MacOS/`.
3. FR-1…FR-46 реализованы; отклонения в Orca pod memory (≤3; исключение тестов — мандат владельца, фиксируется отдельно). Семантика восстановления соответствует D29; ограничение владения (G2 в узком окне аварии) — принятое продуктовое решение, не дефект и не deferral, задокументировано в Orca pod memory и README.
4. UI соответствует `design/HANDOFF.md` (все экраны и состояния, Dark/Light/Contrast); отклонения записаны.
5. EN/RU String Catalog полон из `copy.json`, хардкод-строк нет.
6. AppIcon (все размеры) и 5 menu bar imageset'ов установлены; `CFBundleDisplayName = No-halla`.
7. README (ограничение SIGSTOP ≠ firewall, сборка, запуск, автозапуск, troubleshooting, удаление, чеклист ручной матрицы 20 сценариев), LICENSE MIT, Orca pod memory.
8. Нет телеметрии; исходящие запросы только к IP-endpoint'ам; IP маскируются в логах.
9. Нет force unwrap в production; ошибки обработаны явно; нет `TODO` в critical path; нет идентификаторов Halt.
10. Статические проверки зелёные на каждой стадии и кумулятивно на финальной.

**Не выполняется пайплайном (осознанно, D2/D6):** `./scripts/test.sh` и unit/integration тесты (целиком исключены; test-target'ы и test.sh не создаются в этом запуске — отклонение от брифа §4/§8.10/§9/NFR-6 записывается в Orca pod memory); ручная матрица 20/20 и runtime VoiceOver/контраст-проверки на живом приложении — чеклист для владельца в README. Первый запуск приложения выполняет владелец.

## 12. Что остаётся строителю

Внутренние детали модулей (алгоритмы, приватные хелперы, точная разбивка файлов внутри writeScope плана, моковые данные Preview, внутренности скриптов) — при соблюдении публичных швов, зафиксированных в спецификации и плане. Неплановое изменение публичного интерфейса → возврат к Planner (`PLAN_REVISION_REQUIRED`).

## 13. Риски и mitigation

| Риск | Mitigation |
|---|---|
| IP-endpoint'ы недоступны (в т.ч. в РФ) | Настраиваемые endpoint'ы, backoff, unknown, Resume all; README — как добавить свой |
| Ложная заморозка при переподключении VPN | Grace 5 с, debounce 500 мс, CIDR, bypass после ручного resume |
| PID reuse | Start time перед каждым сигналом |
| Зависшие процессы после краха | Watchdog + startup recovery + resume при штатном выходе |
| Helper-процессы остаются активными | Path-prefix скан внутри `.app`, reconcile 5 с |
| `SMAppService` не работает на ad-hoc подписи | Inline-ошибка, конфиг не меняется молча |
| `EPERM`/`ESRCH` | Пропуск+лог / удаление из трекинга, без падений |
| Утечка IP в логи | Маскирование, полный IP только debug |
| XcodeGen отсутствует | Установка через brew (D17); при неудаче — BLOCKED с инструкцией |
| SVG в asset catalog не отрендерится | Fallback: растеризация qlmanage (D9) |
| `SIGSTOP` ≠ firewall | Честная формулировка в README/About; не обещать zero leak |
| Без тестов нет автоматического доказательства freeze/resume | Статические проверки + строгое ревью кода (режим full); ручная матрица — владельцу |
| Восстановление может снять чужую паузу в узком окне аварии (G2, D29) | Принято владельцем: экспозиция сужена SafetyGuard (выбранный .app, текущий uid, не deny-list); сценарий требует другого агента, останавливающего процесс внутри защищённого bundle точно в окне аварии; документировано в Orca pod memory/README; перенос записи после SIGSTOP запрещён (ломает G1) |
| `OSLogStore` может не отдать логи в ad-hoc-бандле | Экспорт отдаёт доступное (config/state/версии) + пометка о неполных логах; проверка полноты — в чеклисте владельца (FR-32) |

## 14. Открытые вопросы дизайна — статус

Все закрыты. `design/OPEN_QUESTIONS.md`: grace range → D24; Cancel during grace → D25; Repository link → D26. Builder-check (researcher, 2026-11-19): достижимость `disabled` → D27; политика непроверяемого IPv6 → D28; отсутствующие/параметризуемые строки → D22; смена языка без перезапуска → D12 (ред.); Esc в MenuBarExtra → D23. `design/OPEN_QUESTIONS.md` обновляется Implementer'ом в S3 (вопросы закрыты решениями владельца).

## 15. Ревизия C2 (2026-11-19)

**Источник:** `PLAN_REVISION_REQUIRED [plan=plan-v1, stage=S3, chief-cycle=1]` от Implementer; Chief C2/R9 (`chief-attempt4.md`, цикл 1 попытка 4 — бюджет расширен решением владельца), полный анализ `.orca-pod/reports/plan-v1/C2-guarantee-conflict.md`.
**Конфликт:** G1 (FR-41/42: каждое остановленное No-halla приложение возобновляется после аварии, включая окно «SIGSTOP прошёл — подтверждение не записано») vs G2 (критерий Chief: восстановление не снимает чужую паузу). При identity-only журнале оба гарантировать в окне аварии до подтверждения невозможно (pre-write intent байт-идентичен для «остановила и упала» и «не успела остановить»; post-write confirmation теряет G1). Это фундаментальное ограничение crash-consistency, не дефект кода; реальные гонки C2 закрыты в раундах 1–4 (единый владелец журнала, лок callback, откат, re-check identity, inactive guard).
**Решение владельца (блиц ревизии):** вариант **D** — подтвердить identity-checked intent recovery (буквальный FR-42, G1 полностью), принять и задокументировать узкий остаточный риск G2 (D29). B и C отклонены.
**Затронутые TODO:** s2-controller (журнал), s2-watchdog (восстановление), s1-engine (recoverStaleFrozen); документация — s3-final (Orca pod memory, README). Код семантики на HEAD 381e613 уже соответствует D29; ревизия закрепляет решение и документацию, новую семантику не вводит.
**Что не меняется:** все остальные решения D1–D28, стадии, волны, writeScope, проверки; реестр C1/C3/C4 и закрытых гонок сохраняется.

## Журнал блица

- Раунд 1 (2026-11-19): спрошены пункты 1–5 (отсрочка, отмена, ссылка, тумблер, IPv6); все пять приняты по предложению: предел отсрочки 120 с (D24); отмена — немедленная перепроверка без поблажки (D25); строка репозитория скрыта до появления адреса (D26); добавлен переключатель «Защита» (D27); непроверяемый IPv6 — режим «не могу проверить» (D28). Открытых пунктов нет.
- Раунд ревизии C2 (2026-11-19): спрошен 1 пункт (поведение восстановления после аварии); ответ — «Полное восстановление» (вариант D): identity-checked intent recovery по брифу (G1), узкий остаточный риск владения принят и документируется (D29); варианты B и C отклонены. Изменены: реестр решений (D29), §7 надёжность, §11 приёмка, §13 риски, новый §15.