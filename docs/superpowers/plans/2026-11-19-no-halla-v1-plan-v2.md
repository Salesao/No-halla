# No-halla v1 Implementation Plan

> **For agentic workers:** исполнитель — orca-pod Implementer (Integrator) с параллельными `worker`-детьми; flow governed by orca-pod SKILL (стадии → волны → integration → verificationChecks → один REVIEW_REQUEST на стадию; режим `full`: Reviewer принимает стадии, Chief Reviewer выдаёт FINAL_APPROVED). Шаги — checkbox (`- [ ]`). TDD/test-шаги исключены: `tests: not requested` (мандат владельца, spec D2) — это переопределяет TDD-шаги writing-plans. Self-review кода Implementer'ом запрещён при наличии Reviewer (orca-pod Invariants).

**Goal:** Реализовать No-halla v1 целиком (майлстоуны M1–M6 брифа) — menu bar агент macOS 13+, замораживающий выбранные приложения при недоверенном внешнем IP, с watchdog, полным UI по дизайну и EN/RU.

**Architecture:** SwiftUI-сцены (MenuBarExtra/Settings/Window) + AppKit-мосты; ядро — actor `ProtectionEngine`, оркестрирующий `NetworkMonitor` → `IPVerifier` → решётку доверия → чистый `ProtectionStateMachine` → `ProcessController` (SIGSTOP/SIGCONT с identity-check) на последовательном исполнителе; атомарные JSON config/state; отдельный executable `NoHallaWatchdog` (kqueue) внутри .app; UI-мост `@MainActor AppState`.

**Tech Stack:** Swift 5.9+ (language mode 5), SwiftUI, AppKit, Foundation, Network, SystemConfiguration, libproc (Darwin), UserNotifications, ServiceManagement, OSLog; XcodeGen; системные python3/sips/zip для ассетов/строк/диагностики. 0 сторонних зависимостей.

**Spec:** `/Users/salesao/Desktop/worksApp/No-halla/docs/superpowers/specs/2026-11-19-no-halla-v1-spec-v2.md` — ревизия spec-v2 (D29), на утверждении; предыдущая spec-v1@1: `2026-11-19-no-halla-v1-spec.md`. Поведение нормативно по `docs/IMPLEMENTATION_BRIEF.md` (FR-1…46, §5, §8, §13); пиксели/тексты — `docs/DESIGN_BRIEF.md` + `design/` + Doop-канвас `2lgrE5QsCb` (маппинг экранов — `design/HANDOFF.md`).

**Revision:** plan-v2 — ревизия plan-v1@1 по `PLAN_REVISION_REQUIRED` (C2: конфликт гарантий восстановления G1/G2; `chief-attempt4.md`, `.orca-pod/reports/plan-v1/C2-guarantee-conflict.md`). Решение владельца — spec D29 (вариант D: identity-checked intent recovery, G1 полностью; узкий остаточный риск G2 принят и документируется). **Затронутые TODO:** s2-controller, s2-watchdog, s1-engine (recoverStaleFrozen) + документация s3-final (Orca pod memory, README). Код семантики на HEAD 381e613 уже соответствует D29; ревизия закрепляет решение и документацию, новую семантику восстановления не вводит. Остальные TODO, стадии, волны, writeScope и проверки без изменений; реестр C1/C3/C4 и закрытых гонок C2 сохраняется.

**Profile:** ChainaPower · **Review mode:** full · **LANGUAGE:** ru · **Concurrent subagents:** до 12
**Additional skills:** Implementer=graphify, impeccable, verification-before-completion; Reviewer=graphify, verification-before-completion; Chief Reviewer=graphify, verification-before-completion; Planner=graphify, impeccable, brainstorming, writing-plans, plan-blitz, using-superpowers.
**tests:** not requested — тесты не писать, не менять, не запускать; test-target'ы и `scripts/test.sh` НЕ создаются (отклонение от брифа §4/§8.10/§9/NFR-6 → Orca pod memory, мандат владельца).

## Global Constraints

- macOS 13.0+, universal `arm64 x86_64`; Swift language mode 5 (`SWIFT_VERSION: "5.0"`); Xcode 27.2 установлен, XcodeGen ставится через brew (spec D17).
- Восстановление после аварии — по spec D29: identity-checked intent recovery (приоритет G1, буквальный FR-42); запись-интент до SIGSTOP; перенос записи после SIGSTOP и игнорирование pending запрещены; узкое ограничение владения (G2) принято владельцем и документируется (Orca pod memory, README). Новую семантику восстановления без согласования не вводить.
- Только системные фреймворки; 0 зависимостей; без приватных API; libproc — публичный.
- Sandbox OFF (`NoHalla.entitlements` — пустой словарь), Hardened Runtime ON, ad-hoc подпись `CODE_SIGN_IDENTITY: "-"`, без root.
- Идентификаторы: UI/доки — `No-halla`; код/модуль — `NoHalla`; bundle ID `dev.nohalla.NoHalla`, watchdog `dev.nohalla.NoHallaWatchdog`; watchdog-бинарник в `No-halla.app/Contents/MacOS/NoHallaWatchdog`; support dir `~/Library/Application Support/NoHalla/`; OSLog subsystem `dev.nohalla.NoHalla`.
- Все UI-строки EN/RU — из `design/copy.json` через String Catalog (расширения — spec D22); хардкод строк запрещён (FR-30); цвета/отступы — из `design/tokens.json` (FR §8.8), без кастомных шрифтов; бронза — только декор (D3).
- IP маскировать в логах вне debug (`203.0.113.x`); исходящий трафик — только IP-endpoint'ы; без телеметрии.
- Без force unwrap в production (NFR-7); ошибки явно; без `TODO`/`FIXME` в critical path (Core/Process, Core/Engine, Core/Watchdog, NoHallaWatchdog).
- UI-обновление ≤200 мс после смены состояния; countdown ±100 мс; reconcile не чаще 5 с; freeze новых экземпляров ≤2 с.
- Коммиты — логическими блоками по `docs/commit.md` (`type: description`, 30–50 символов, lowercase present-tense verb, без точки); разрешены брифом §12.8; **push запрещён**. `.orca-pod/` не входит в writeScope и коммиты.
- Каждая SwiftUI view — Preview с моковыми состояниями (бриф §8.8).
- Публичные интерфейсы ниже обязательны; unplanned изменение публичного интерфейса → `PLAN_REVISION_REQUIRED` к Planner.

## Review Focus

Тестов нет (D2); эти пять режимов отказа закреплены как acceptance-критерии владеющих задач и проверяются ревью кода (Reviewer/Chief) против названных FR:

1. **PID reuse между перечислением и сигналом** → start time сверяется перед каждым `kill`; несовпал — пропуск (FR-18/19, §8.4) — s2-controller, s2-watchdog.
2. **Обход deny-list/uid/path-prefix** → себя, watchdog, PID 1, системные процессы, чужой uid, путь вне `.app` никогда не сигналить; пропуск+лог (FR-17/45) — s2-safety, s2-controller.
3. **Крах/выход оставляет приложения замороженными** → watchdog ≤2 с, startup recovery, quit/SIGTERM/SIGINT resume all + очистка state (FR-4/5/6/41/42) — s2-watchdog, s2-lifecycle, s1-engine. Семантика восстановления закреплена spec D29: G1 полностью (включая аварию после SIGSTOP до подтверждения); G2 — узкое принятое ограничение владения, не дефект; документация Orca pod memory/README обязательна.
4. **Неверная композиция IPv4/IPv6/unknown** → ложная заморозка или тихая дыра; решётка D28, quorum per-family, расхождение → unknown, офлайн без запросов (FR-8/11/13/14) — s1-ipverify, s1-engine.
5. **Гонки таймеров после wake/дребезга сети** → debounce 500 мс, немедленная проверка после wake без «догона», не более 1 батча, backoff 5→60 с, последовательные freeze/resume (FR-7/9/12/44/46) — s1-netmon, s1-engine, s2-controller.

## Verification Checks (статические; выполняются Implementer'ом после последней волны стадии; на S3 — кумулятивно)

1. `xcodegen generate` — exit 0.
2. `xcodebuild -project NoHalla.xcodeproj -scheme NoHalla -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="-" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build` — exit 0 (компиляция/типизация всего кода).
3. `plutil -lint NoHalla/App/Info.plist` — exit 0 (S3).
4. `test -x "build/Build/Products/Release/No-halla.app/Contents/MacOS/NoHallaWatchdog"` — exit 0 (S2, S3).
5. `test -d "build/Build/Products/Release/No-halla.app/Contents/Resources/Assets.car"` и наличие AppIcon/5 menubar imageset в исходном каталоге (S3).
6. `grep -RInE "Halt|dev\.halt" NoHalla NoHallaWatchdog project.yml scripts` — нет совпадений (S3).
7. `grep -RInE "TODO|FIXME" NoHalla/Core/Process NoHalla/Core/Engine NoHalla/Core/Watchdog NoHallaWatchdog` — нет совпадений (S3).
8. python3-сверка: все ключи `design/copy.json` присутствуют в `Localizable.xcstrings` с EN и RU (S3).

**verificationRationale:** статический гейт Swift — компилятор; линтер в проекте не настроен (не добавляем без запроса); runtime-проверки исключены spec D6 (приложение пайплайном не запускается; первый запуск и ручная матрица 20 сценариев — чеклист владельца в README). Test-команд нет: `tests: not requested`.
**Diagnostic owner (full mode):** Reviewer — кумулятивный проход на первой попытке последней стадии (S3); точечные диагностики по проблемам — ранее. Read-only проверки Reviewer'а: чтение кода/ снапшота, `xcodebuild build` как typecheck НЕ использовать (build — проверка Implementer'а); grep/plutil/test допустимы read-only.

## File Structure

```
project.yml, .gitignore
NoHalla/App/{NoHallaApp,NoHallaAppDelegate,AppState}.swift, Info.plist
NoHalla/Core/Models/{AppConfig,ProtectedApp,ProtectionState,FrozenProcess,TrustedAddress}.swift
NoHalla/Core/Config/{ConfigStore,StateStore}.swift
NoHalla/Core/Logging/AppLog.swift
NoHalla/Core/Network/{CIDR,NetworkMonitor,IPVerifier}.swift
NoHalla/Core/Process/{ProcessControlling,LoggingProcessController,ProcessEnumerator,SafetyGuard,ProcessController}.swift
NoHalla/Core/Engine/{ProtectionStateMachine,ProtectionEngine}.swift
NoHalla/Core/Notifications/NotificationCoordinator.swift
NoHalla/Core/Watchdog/WatchdogLauncher.swift
NoHalla/Core/Diagnostics/DiagnosticsExporter.swift
NoHalla/UI/Theme/DesignTokens.swift
NoHalla/UI/Localization/L10n.swift
NoHalla/UI/Components/{StatusPillView,AppRowView,GateRuleView,GateSceneView,NetworkCardView,CountdownBarView,SettingRowView,QuitConfirmationAlert}.swift
NoHalla/UI/Popover/PopoverView.swift (+подвиды)
NoHalla/UI/Onboarding/{OnboardingContainerView,OnboardingIntroView,OnboardingAppsView,OnboardingTrustedRealmView}.swift
NoHalla/UI/Settings/{SettingsRootView,SettingsGeneralView,SettingsProtectionView,SettingsAdvancedView,SettingsAboutView,TrustedAddressEditor,EndpointEditor,ResetSettingsAlert}.swift
NoHalla/UI/AppPicker/AppPickerSheet.swift
NoHalla/Resources/Assets.xcassets (AppIcon.appiconset, MenuBarProtected/Grace/Frozen/Unknown/Off.imageset, GateScene.imageset), Localizable.xcstrings
NoHalla/NoHalla.entitlements
NoHallaWatchdog/main.swift
scripts/{build.sh,run.sh,gen-strings.py,gen-assets.py}
README.md, LICENSE, Orca pod memory (append), design/OPEN_QUESTIONS.md (update), design/copy.json (аддитивно, D22)
```

Дополнения к layout брифа §4 (фиксируются в Orca pod memory): `Core/Logging/`, `Core/Notifications/` (D13), `Core/Process/ProcessControlling.swift` (шов D8), `UI/Theme/`, `UI/Localization/`, `App/AppState.swift`.

## Стадии и волны

| Стадия | Волны (параллельно внутри волны) | Integration (Integrator) |
|---|---|---|
| S1 = M1+M2 | W1: s1-models, s1-cidr, s1-assets, s1-netmon → W2: s1-statemachine, s1-ipverify, s1-seam, s1-strings → W3: s1-engine | s1-scaffold (до W1), s1-wiring (после W3) → checks → REVIEW_REQUEST |
| S2 = M3+M4 | W1: s2-enumerator, s2-safety, s2-watchdog, s2-notifications → W2: s2-controller, s2-lifecycle | s2-wiring (после W2) → checks → REVIEW_REQUEST |
| S3 = M5+M6 | W1: s3-components, s3-diagnostics, s3-apppicker → W2: s3-popover, s3-onboarding, s3-settings-general, s3-settings-protection, s3-settings-advanced | s3-final (после W2) → кумулятивные checks → REVIEW_REQUEST (final stage) |

Пик параллельности: 5 (S3 W2) ≤ 12. Стадия открывается только после `APPROVED` предыдущей. Зависимости внутри волн исключены: s1-strings использует AppLanguage (s1-models) → W2; s3-apppicker нужен поповеру и Protection-вкладке → W1; SettingsRootView (TabView всех вкладок) создаётся в s3-final.

---

## Stage S1 — Scaffold + ядро (M1+M2)

### s1-scaffold (integration, Integrator, до волн)

**Files:** Create: `project.yml`, `.gitignore`, `NoHalla/App/Info.plist`, `NoHalla/NoHalla.entitlements`, `scripts/build.sh`, `scripts/run.sh`, `NoHallaWatchdog/main.swift` (скелет), `NoHalla/App/NoHallaApp.swift` (минимальный), `NoHalla/App/NoHallaAppDelegate.swift` (минимальный).
**Interfaces / Produces:** структура каталогов по File Structure; `project.yml` — targets `NoHalla` (application) и `NoHallaWatchdog` (tool, embed+codeSign), scheme `NoHalla`, settings брифа §8.10 БЕЗ test-target'ов; `ARCHS arm64 x86_64`, `ONLY_ACTIVE_ARCH NO`, `SWIFT_VERSION 5.0`, deployment 13.0, `PRODUCT_NAME No-halla`, `PRODUCT_MODULE_NAME NoHalla`, `INFOPLIST_FILE NoHalla/App/Info.plist`, `CODE_SIGN_ENTITLEMENTS NoHalla/NoHalla.entitlements`, `ENABLE_HARDENED_RUNTIME YES`, `CODE_SIGN_IDENTITY "-"`. Info.plist: `LSUIElement true`, `LSMinimumSystemVersion 13.0`, `CFBundleDisplayName/CFBundleName No-halla`, `CFBundleIdentifier $(PRODUCT_BUNDLE_IDENTIFIER)`, `CFBundleShortVersionString 0.9.0`, `NSHumanReadableCopyright MIT`. build.sh — бриф §8.10 + universal-флаги; run.sh — `open build/Build/Products/Release/No-halla.app`. Watchdog-скелет: парсинг `--parent <pid> --state <path>`, если родитель не существует — exit 0 (kqueue — s2-watchdog). Минимальный App: `MenuBarExtra` со статическим `Image("MenuBarOff")` и placeholder-поповером `Text("No-halla")`; AppDelegate — пустой lifecycle.
**Steps:**
- [ ] Установить XcodeGen: `brew install xcodegen`; контроль `xcodegen --version`.
- [ ] Создать файлы выше; каталоги по File Structure.
- [ ] `xcodegen generate && ./scripts/build.sh` — exit 0; `No-halla.app` собирается.
- [ ] Commit `build: scaffold xcodegen project and app skeleton`.
**Acceptance:** сборка зелёная; watchdog-бинарник в `Contents/MacOS/` (embed); идентификаторы по Global Constraints.
**Stop:** brew/xcodegen недоступен → BLOCKED с инструкцией (spec D17); embed разместил watchdog иначе → copy-files phase в project.yml (бриф §4).

### s1-models (wave 1)

**Files:** Create: `NoHalla/Core/Models/AppConfig.swift`, `ProtectedApp.swift`, `ProtectionState.swift`, `FrozenProcess.swift`, `TrustedAddress.swift`, `NoHalla/Core/Config/ConfigStore.swift`, `StateStore.swift`, `NoHalla/Core/Logging/AppLog.swift`.
**dependsOn:** s1-scaffold. **writeScope:** `NoHalla/Core/Models/`, `NoHalla/Core/Config/`, `NoHalla/Core/Logging/`.
**Interfaces / Produces:**
- `struct AppConfig: Codable, Equatable` — `schemaVersion: Int`, `onboardingCompleted: Bool`, `protection: ProtectionSettings`, `trustedAddresses: [String]`, `protectedApps: [ProtectedApp]`, `ipCheck: IPCheckSettings`, `launchAtLogin: Bool`, `notifications: Bool`, `language: AppLanguage`, `logLevel: LogLevel`; `static let defaults: AppConfig` — бриф §13 + `logLevel .info` (D11).
- `struct ProtectionSettings: Codable, Equatable` — `enabled, graceSeconds, checkIntervalSeconds, freezeWhenUnknown, checkIPv6, requireVPNInterface, manualResumeBypassMinutes`.
- `struct IPCheckSettings: Codable, Equatable` — `endpointsV4: [String]`, `endpointsV6: [String]`, `timeoutSeconds: Double`, `quorum: Int` (дефолты брифа §5.4).
- `enum AppLanguage: String, Codable { case system, en, ru }`; `enum LogLevel: String, Codable { case info, debug }`.
- `struct ProtectedApp: Codable, Equatable, Identifiable` — `bundleID, name, enabled`; `var id: String { bundleID }`.
- `struct FrozenProcess: Codable, Equatable` — `pid: Int32, startTimeSec: Int64, startTimeUsec: Int64, bundleID: String, path: String`.
- `enum ProtectionStatus: String, Codable { case initializing, checking, protected, grace, frozen, unknown, paused, disabled }`; `enum FreezeReason: String, Codable { case ipDisallowed, unknown }`; `enum PauseDuration { case minutes15, hour1, untilRelaunch }`; `enum UIStatus { case setup, checking, protected, grace, frozen, unknown, paused, disabled, bypassing }`.
- `struct TrustedAddress: Codable, Equatable` — `raw: String`; `func matches(_ ip: IPAddress) -> Bool` (через CIDRRange, s1-cidr); `var isValid: Bool`.
- `final class ConfigStore` — `init(directory: URL = ConfigStore.defaultDirectory)`; `static var defaultDirectory: URL`; `func load() -> AppConfig` (валидация → дефолты повреждённых полей + лог + `lastLoadWasCorrupt`); `func save(_ config: AppConfig) throws` (temp+replaceItemAt, атомарно); `private(set) var lastLoadWasCorrupt: Bool`; миграция по `schemaVersion`.
- `struct PersistedState: Codable` — `schemaVersion: Int, frozen: [FrozenProcess], frozenSince: Date?, reason: FreezeReason?, lastKnownIP: String?`; `final class StateStore` — `init(directory: URL = ConfigStore.defaultDirectory)`, `func load() -> PersistedState?`, `func save(_ state: PersistedState) throws`, `func clear() throws` (атомарно).
- `enum AppLog` — `static let subsystem = "dev.nohalla.NoHalla"`; категории `network, engine, process, ui, watchdog` (`os.Logger`); `static func maskIP(_ ip: String) -> String` (IPv4: последний октет → `x`; IPv6: последняя группа → `x`); info-логи IPs только masked, debug — полный (FR-39).
**Consumes:** `IPAddress`/`CIDRRange` из s1-cidr (параллельная задача; контракт ниже — писать против него).
**Steps:**
- [ ] Реализовать модели + дефолты брифа §5.4/§13 (+logLevel D11).
- [ ] Валидация ConfigStore: `graceSeconds 0...120` (D24), `checkIntervalSeconds 10...120` (D19), `manualResumeBypassMinutes 0...60`, `quorum >= 1`, `timeoutSeconds > 0`, endpoints — валидные HTTPS URL, trustedAddresses — парсимые (невалидные отбрасывать+лог); битый JSON → defaults + lastLoadWasCorrupt.
- [ ] Атомарная запись обоих хранилищ; миграция schemaVersion=1.
- [ ] AppLog с маскированием; сборка `./scripts/build.sh` — exit 0.
- [ ] Commit `feat: add config models and atomic stores`.
**Acceptance:** компилируется; диапазоны валидации по D24/D19/D11; атомарность; corrupt→defaults+flag+лог; маскирование IP.
**Stop:** конфликт контракта CIDR → вопрос Integrator'у (не менять публичный интерфейс молча).

### s1-cidr (wave 1)

**Files:** Create: `NoHalla/Core/Network/CIDR.swift`.
**dependsOn:** s1-scaffold. **writeScope:** `NoHalla/Core/Network/CIDR.swift`.
**Interfaces / Produces:** `enum IPFamily { case v4, v6 }`; `struct IPAddress: Equatable, CustomStringConvertible` — `let bytes: [UInt8]` (4/16), `var family: IPFamily`, `init?(_ string: String)` (inet_pton AF_INET/AF_INET6, trim whitespace), `var masked: String`; `struct CIDRRange: Equatable` — `let address: IPAddress`, `let prefixLength: Int`, `init?(_ string: String)` (одиночный IP → /32 или /128; `a/b` с валидным prefix 0...32/0...128), `func contains(_ ip: IPAddress) -> Bool` (битовая маска, family match).
**Steps:**
- [ ] Реализовать парсинг и matching по брифу §8.3 (включая /0, /32, /128, невалидные строки → nil).
- [ ] Сборка — exit 0. Commit `feat: add ipv4 and ipv6 cidr matching`.
**Acceptance:** компилируется; одиночный IP = /32//128; cross-family contains → false; невалидное → nil.

### s1-assets (wave 1)

**Files:** Create: `scripts/gen-assets.py`, `NoHalla/Resources/Assets.xcassets/**` (AppIcon.appiconset, MenuBarProtected/Grace/Frozen/Unknown/Off.imageset, GateScene.imageset, Contents.json), `NoHalla/UI/Theme/DesignTokens.swift`.
**dependsOn:** s1-scaffold. **writeScope:** `scripts/gen-assets.py`, `NoHalla/Resources/Assets.xcassets/`, `NoHalla/UI/Theme/`.
**Interfaces / Produces:** `enum DesignTokens` — статические `Color` (динамические light/dark через `NSColor(name:dynamicProvider:)`, contrast-варианты по tokens.json `appearance[2]`), размеры/отступы/radii/шрифты **дословно из `design/tokens.json`** (popoverWidth 360, settings 680×520, onboarding 560×420, picker 480×520, appRow 44, appIcon 20, menuBar 18, statusHeight 22, targetMin 28, spacing 4/8/12/16/24, radii 6/10/14/11, type body 13/small 11/title 17/hero 23). Маппинг статус→имя глифа создаётся в s1-wiring (зависит от UIStatus из s1-models).
**Steps:**
- [ ] gen-assets.py (python3 stdlib + sips): AppIcon все macOS-размеры из `design/exports/appicon-1024.png`; разрезать `design/exports/menubar-icons.svg` на 5 отдельных SVG (symbol id → imageset, viewBox 18×18, `preserves-vector-representation: true`, template rendering intent); GateScene — декоративный SVG (геометрия ворот/фьорда из hero `design/mockups/onboarding-1.html` / `brand-sheet.svg`).
- [ ] Запустить скрипт, каталог валиден; DesignTokens по tokens.json.
- [ ] Сборка — exit 0. Commit `feat: add brand assets and design tokens`.
**Acceptance:** AppIcon 16…1024 на месте; 5 imageset'ов с именами §0 брифа; токены совпадают с tokens.json; скрипт воспроизводим.
**Stop:** SVG в каталоге не рендерится → fallback растеризация `qlmanage` (spec D9), записать в Orca pod memory.

### s1-strings (wave 2)

**Files:** Create: `scripts/gen-strings.py`, `NoHalla/Resources/Localizable.xcstrings`, `NoHalla/UI/Localization/L10n.swift`; Modify: `design/copy.json` (аддитивно, D22).
**dependsOn:** s1-scaffold, s1-models (AppLanguage). **writeScope:** `scripts/gen-strings.py`, `NoHalla/Resources/Localizable.xcstrings`, `NoHalla/UI/Localization/`, `design/copy.json`.
**Interfaces / Produces:** `enum L10n` — `static var current: AppLanguage` (system → Locale.preferredLanguages), `static func string(_ key: String, _ args: CVarArg...) -> String` (lookup в bundle выбранного языка en.lproj/ru.lproj из Bundle.main; fallback EN; без перезапуска, D12); генератор copy.json → xcstrings (EN sourceLanguage + RU translations, ключи = dotted-ключи).
**Steps:**
- [ ] D22-расширение copy.json: новые ключи EN+RU в тоне дизайн §9 — баннер битого конфига (title/body), `ui.log-level-info`/`ui.log-level-debug`, единицы s/min, переключатель «Защита» (D27: label + helper); параметризовать `caption.resumeBypass` (%d minutes), `ui.checking-resumes-at-14-32` (%@), `ui.2-apps-selected` (%d), `ui.version-0-1-0` (%@); остальные мок-литералы по мере обнаружения (аддитивно, оригиналы сохранять где совместимо).
- [ ] gen-strings.py + сгенерировать xcstrings; L10n-хелпер.
- [ ] Сборка — exit 0. Commit `feat: add string catalog and localization helper`.
**Acceptance:** все ключи copy.json в каталоге EN+RU; параметризованные ключи без мок-чисел; L10n переключает язык in-process; новые тексты записаны для Orca pod memory (список передаётся Integrator'у).
**Stop:** —

### s1-netmon (wave 1)

**Files:** Create: `NoHalla/Core/Network/NetworkMonitor.swift`.
**dependsOn:** s1-scaffold. **writeScope:** `NoHalla/Core/Network/NetworkMonitor.swift`.
**Interfaces / Produces:** `final class NetworkMonitor` — `init(debounce: TimeInterval = 0.5)`, `var onEvent: (() -> Void)?` (сеть сменилась / wake), `func start()`, `func stop()`, `var isOnline: Bool`, `func vpnInterfaceName() -> String?` (getifaddrs: utun*/ipsec*/ppp*/tun* с ifa_addr). Источники: NWPathMonitor(.any), SCDynamicStore notification keys (IP/маршруты), NSWorkspace.didWakeNotification. Периодический таймер проверки — в engine (не здесь).
**Steps:**
- [ ] Реализовать по брифу §8.1: debounce 500 мс (собрать события → один onEvent), wake-событие, online-статус; без проверок во сне (engine решает).
- [ ] Сборка — exit 0. Commit `feat: add network path and wake monitor`.
**Acceptance:** компилируется; debounce; VPN-детект по именам интерфейсов; stop освобождает ресурсы.

### s1-statemachine (wave 2)

**Files:** Create: `NoHalla/Core/Engine/ProtectionStateMachine.swift`.
**dependsOn:** s1-models. **writeScope:** `NoHalla/Core/Engine/ProtectionStateMachine.swift`.
**Interfaces / Produces:** `enum ProtectionEvent { case appStarted(configValid: Bool), networkChanged, ipAllowed, ipDisallowed, noQuorum, graceExpired, freezeNowTapped, cancelTapped, resumeAllTapped, pauseRequested(PauseDuration), pauseExpired, turnOnNowTapped, protectionEnabled, protectionDisabled, bypassExpired }`; `enum Effect { case startGrace(seconds: Int), cancelGrace, freeze(reason: FreezeReason), resumeAll, startBypass(minutes: Int), cancelBypass, startPause(PauseDuration), cancelPause, immediateCheck, clearFrozenState }`; `struct ProtectionStateMachine` — `private(set) var status: ProtectionStatus`, `init()`, `mutating func reduce(_ event: ProtectionEvent, env: Environment) -> [Effect]`; `struct Environment { freezeWhenUnknown: Bool, graceSeconds: Int, bypassMinutes: Int, trustedEmpty: Bool }`. Чистая, без I/O.
**Steps:**
- [ ] Реализовать ВСЕ переходы таблицы брифа §5.3 + D25 (`cancelTapped` в grace → `immediateCheck` → checking, без bypass) + D27 (`protectionDisabled` → resumeAll + disabled; `protectionEnabled` → checking) + bypass (`resumeAllTapped` в frozen → resumeAll + startBypass + protected; `bypassExpired` → immediateCheck) + pause (resumeAll + startPause + paused; pauseExpired/turnOnNow → checking).
- [ ] `setup`/`bypassing` — НЕ состояния машины (производные в AppState, бриф §5.3).
- [ ] Сборка — exit 0. Commit `feat: add pure protection state machine`.
**Acceptance:** компилируется; таблица §5.3 покрыта полностью (ревью сверяет построчно); unknown+freezeWhenUnknown=false не морозит; до первой успешной проверки (appStarted→checking) freeze невозможен.

### s1-ipverify (wave 2)

**Files:** Create: `NoHalla/Core/Network/IPVerifier.swift`.
**dependsOn:** s1-models, s1-cidr. **writeScope:** `NoHalla/Core/Network/IPVerifier.swift`.
**Interfaces / Produces:** `enum FamilyResult { case verified(IPAddress), noQuorum, notApplicable }`; `struct IPVerificationResult { let ipv4: FamilyResult, let ipv6: FamilyResult, let currentIPv4: IPAddress?, let currentIPv6: IPAddress? }`; `actor IPVerifier` — `init()`, `func check(config: AppConfig, online: Bool) async -> IPVerificationResult?` (nil = throttled/backoff, engine сохраняет текущее состояние). URLSessionConfiguration.ephemeral, timeoutIntervalForRequest 2.5 / resource 4 (из config.ipCheck.timeoutSeconds), withTaskGroup параллельно; ответ plain-text IP или JSON `ip`; валидация IPAddress; quorum per-family; расхождение успешных ответов семьи → noQuorum; IPv6 выключен/egress нет → notApplicable; offline → noQuorum без запросов; батч не чаще 3 с; backoff 5→60 с при ошибках; не более 1 батча; редиректы на другие хосты запрещены/проверяются (NFR-8); логи masked (AppLog).
**Steps:**
- [ ] Реализовать по брифу §8.2/FR-8/9; IPv6-egress определять по наличию адреса (getifaddrs через NetworkMonitor не тянуть — простой socket/connect-check или NWPath; решение внутри модуля).
- [ ] Сборка — exit 0. Commit `feat: add quorum ip verifier with backoff`.
**Acceptance:** компилируется; quorum/расхождение/offline/throttle/backoff семантика FR-8/9; только HTTPS; IP masked в логах.

### s1-seam (wave 2)

**Files:** Create: `NoHalla/Core/Process/ProcessControlling.swift`, `NoHalla/Core/Process/LoggingProcessController.swift`.
**dependsOn:** s1-models. **writeScope:** `NoHalla/Core/Process/ProcessControlling.swift`, `NoHalla/Core/Process/LoggingProcessController.swift`.
**Interfaces / Produces:** `protocol ProcessControlling: AnyObject { func freeze(_ apps: [ProtectedApp]) async -> [FrozenProcess]; func resumeAll() async -> [FrozenProcess]; func reconcile(_ apps: [ProtectedApp]) async -> [FrozenProcess]; func currentFrozen() async -> [FrozenProcess] }` (возвращает актуальный список замороженных для StateStore). `final class LoggingProcessController: ProcessControlling` — стадийный шов S1: логирует интенты (AppLog.process), возвращает пустые списки; **удаляется в s2-wiring** (в финальном коде не остаётся).
**Steps:**
- [ ] Протокол + LoggingProcessController; сборка — exit 0. Commit `feat: add process control seam for stage one`.
**Acceptance:** компилируется; форма протокола совпадает с контрактом (s2-controller реализует его).

### s1-engine (wave 3)

**Files:** Create: `NoHalla/Core/Engine/ProtectionEngine.swift`.
**dependsOn:** s1-models, s1-cidr, s1-netmon, s1-statemachine, s1-ipverify, s1-seam. **writeScope:** `NoHalla/Core/Engine/ProtectionEngine.swift`.
**Interfaces / Produces:** `struct EngineSnapshot { let status: ProtectionStatus, let uiStatus: UIStatus, let currentIPv4: String?, let currentIPv6: String?, let vpnInterface: String?, let trusted: Bool, let graceRemaining: Int?, let bypassUntil: Date?, let pauseUntil: Date?, let frozenBundleIDs: Set<String>, let runningBundleIDs: Set<String>, let lastCheck: Date? }` (IP — masked для UI? нет: UI показывает полный IP пользователю, маскируются только логи); `enum UserAction { case freezeNow, cancelGrace, resumeAll, pause(PauseDuration), turnOnNow, retryCheck, addCurrentIP, setProtectionEnabled(Bool), configChanged(AppConfig) }`; `struct NotificationEvent { let kind: NotificationKind, let frozenCount: Int }`; `enum NotificationKind { case frozen, resumed, unknown }`; `actor ProtectionEngine` — `init(configStore: ConfigStore, stateStore: StateStore, controller: ProcessControlling, verifier: IPVerifier, monitor: NetworkMonitor)`, `var onSnapshot: ((EngineSnapshot) -> Void)?`, `var onNotification: ((NotificationEvent) -> Void)?`, `func start() async`, `func stop() async` (resume all + clear state), `func handle(_ action: UserAction) async`, `func recoverStaleFrozen() async`.
**Steps:**
- [ ] Оркестрация по брифу §5.2/FR-7…14: monitor.onEvent → debounce-проверка; periodic timer checkIntervalSeconds; wake → немедленная проверка + пересоздание таймеров; verifier.check → решётка D28 (любой disallowed → disallowed; иначе любой unknown → unknown; иначе allowed; requireVPNInterface без туннеля → disallowed; trustedEmpty → setup-представление, freeze не инициировать) → stateMachine.reduce → исполнение Effects.
- [ ] Таймеры: grace (countdown ±100 мс, отмена при allowed), bypass (по истечении immediateCheck), pause (15/60/untilRelaunch), reconcile 5 с (controller.reconcile + persist), throttle сна.
- [ ] Freeze/resume через controller последовательно (actor); после каждой операции StateStore.save/clear; snapshot-публикация ≤200 мс; onNotification при frozen/resumed/unknown (throttle — в coordinator S2).
- [ ] `recoverStaleFrozen`: state.frozen → controller.resumeAll (identity-check внутри контроллера S2) → clear — семантика D29 (G1 полностью; узкое ограничение владения принято, документация через s3-final); `addCurrentIP`: добавить текущий IPv4 (+IPv6 если verified) в trusted → immediateCheck; `configChanged`: перечитать настройки, пересоздать таймеры, `setProtectionEnabled(false)` → resumeAll+disabled (D27).
- [ ] UIStatus производный: trustedEmpty → setup; bypassUntil активен → bypassing; иначе status.
- [ ] Сборка — exit 0. Commit `feat: add protection engine orchestration`.
**Acceptance:** компилируется; FR-7…14/20…25 оркестрация; решётка D28; до первой успешной проверки не морозит; офлайн без запросов; операции последовательны; snapshot ≤200 мс; recoverStaleFrozen соответствует D29.
**Stop:** нехватка публичного контракта соседей → Integrator/PLAN_REVISION_REQUIRED.

### s1-wiring (integration, Integrator, после W3)

**Files:** Modify: `NoHalla/App/NoHallaApp.swift`, `NoHallaAppDelegate.swift`; Create: `NoHalla/App/AppState.swift`, `NoHalla/UI/Popover/PopoverView.swift` (placeholder S1).
**writeScope:** `NoHalla/App/`, `NoHalla/UI/Popover/` (placeholder), `project.yml` (правки).
**Interfaces / Produces:** `@MainActor final class AppState: ObservableObject` — `@Published var snapshot: EngineSnapshot`, `@Published var config: AppConfig`, `@Published var corruptConfigBanner: Bool`, `@Published var notificationsDenied: Bool`, `@Published var launchAtLoginError: String?`, `var uiStatus: UIStatus`, `func send(_ action: UserAction)` (Task → engine.handle), `func setConfig(_ config: AppConfig)` (ConfigStore.save + engine.configChanged), `func requestNotificationPermission()` (S2 wiring подключает coordinator); `extension DesignTokens { static func menuBarImageName(for status: UIStatus) -> String }` — маппинг ICONS.md (protected→MenuBarProtected; checking/grace→MenuBarGrace; frozen→MenuBarFrozen; unknown/setup→MenuBarUnknown; paused/disabled/bypassing→MenuBarOff); `NoHallaApp` — `MenuBarExtra` с динамическим `Image(DesignTokens.menuBarImageName(for:))` `.renderingMode(.template)`, `.menuBarExtraStyle(.window)`, placeholder-поповер (статус + lore через L10n), `Settings` placeholder; AppDelegate — flock single-instance (support dir), ConfigStore.load, engine.start с LoggingProcessController, stop при выходе.
**Steps:**
- [ ] Wire engine.onSnapshot → AppState (MainActor); menu bar icon по uiStatus; placeholder-поповер.
- [ ] verificationChecks стадии S1 (пп.1–2); исправить ошибки.
- [ ] Проверить `No-halla.app/Contents/MacOS/NoHallaWatchdog` (test -x).
- [ ] Commit `feat: wire menu bar app to protection engine`.
- [ ] Сохранить snapshot + REVIEW_REQUEST S1 (TODO→files, baseline HEAD=0f1a83e + dirty-лист, checks, отклонения).
**Acceptance S1:** сборка зелёная; .app + watchdog на месте; конфиг сохраняется (код); статусы engine достижимы на моках; state machine чистая.

---

## Stage S2 — Процессы + надёжность (M3+M4)

### s2-enumerator (wave 1)

**Files:** Create: `NoHalla/Core/Process/ProcessEnumerator.swift`.
**dependsOn:** S1 APPROVED. **writeScope:** `NoHalla/Core/Process/ProcessEnumerator.swift`.
**Interfaces / Produces:** `struct RunningProcess { let pid: Int32, let bundleID: String, let bundlePath: String, let executablePath: String }`; `enum ProcessEnumerator` — `static func instances(of bundleID: String) -> [RunningProcess]` (NSWorkspace.runningApplications(withBundleIdentifier:)), `static func allPIDs() -> [Int32]` (proc_listallpids), `static func path(of pid: Int32) -> String?` (proc_pidpath, PROC_PIDPATHINFO_MAXSIZE), `static func startTime(of pid: Int32) -> (sec: Int64, usec: Int64)?` (proc_pidinfo PROC_PIDTBSDINFO), `static func uid(of pid: Int32) -> UInt32?` (pbi_uid), `static func childPIDs(of pid: Int32) -> [Int32]` (proc_listchildpids), `static func processes(insideBundleAt path: String) -> [Int32]` (path-prefix скан allPIDs).
**Steps:**
- [ ] Реализовать по брифу §8.4 (публичный libproc, буферы корректного размера, без force unwrap).
- [ ] Сборка — exit 0. Commit `feat: add process enumeration via libproc`.
**Acceptance:** компилируется; FR-16 множество (основные+дети+path-prefix); identity-данные доступны.

### s2-safety (wave 1)

**Files:** Create: `NoHalla/Core/Process/SafetyGuard.swift`.
**dependsOn:** S1 APPROVED. **writeScope:** `NoHalla/Core/Process/SafetyGuard.swift`.
**Interfaces / Produces:** `enum SafetyGuard` — `static let deniedExecutableNames: Set<String>` (kernel_task, WindowServer, Dock, Finder, loginwindow, SystemUIServer, ControlCenter, launchd), `static func isDenied(pid: Int32, path: String, bundleID: String?, selfPID: Int32, watchdogPID: Int32?) -> Bool` (PID 1, deny-list по имени пути/bundle ID, uid ≠ getuid(), себя/watchdog), `static func isInsideBundle(path: String, bundlePath: String) -> Bool` (строгий prefix внутри `.app`, FR-45), `static func pickerWarning(for bundleID: String, name: String) -> String?` (системные/Terminal-подобные: Finder, Dock, Terminal, iTerm и т.п. — предупреждение для UI, ключ copy `ui.freezing-terminal-may-interrupt-active-commands` / `ui.system-app-can-t-be-protected`).
**Steps:**
- [ ] Реализовать deny-list FR-17 полностью + uid + path-prefix; предупреждения picker FR-28.
- [ ] Сборка — exit 0. Commit `feat: add process safety guard deny list`.
**Acceptance:** компилируется; все сущности FR-17 в deny-list; чужой uid отклоняется; путь вне bundle отклоняется.

### s2-watchdog (wave 1)

**Files:** Modify: `NoHallaWatchdog/main.swift` (заменить скелет); Create: `NoHalla/Core/Watchdog/WatchdogLauncher.swift`.
**dependsOn:** S1 APPROVED (StateStore/ PersistedState). **writeScope:** `NoHallaWatchdog/`, `NoHalla/Core/Watchdog/`.
**Interfaces / Produces:** watchdog: аргументы `--parent <pid> --state <path>`; kqueue EVFILT_PROC/NOTE_EXIT на родителя; родитель уже мёртв на старте → exit 0; после NOTE_EXIT: sleep 1 с → прочитать state.json → для каждого PID сверить start time (proc_pidinfo) → SIGCONT → удалить state file; только Foundation/Darwin, без UI, без root. `final class WatchdogLauncher` — `func start(parentPID: Int32, statePath: URL)`, `func stop()`, `private(set) var watchdogPID: Int32?`; Process spawn бинарника из bundle; terminationHandler: не по команде → перезапуск + AppLog.watchdog error.
**Steps:**
- [ ] Реализовать по брифу §5.5/§8.9 (константы Darwin, не хардкодить сигналы).
- [ ] Сборка — exit 0; `test -x .../Contents/MacOS/NoHallaWatchdog`.
- [ ] Commit `feat: add kqueue watchdog and launcher`.
**Acceptance:** компилируется; FR-41 семантика (≤2 с: 1 с wait + сигналы); identity-check перед SIGCONT; штатный выход → пустой state → watchdog завершается; нештатная смерть watchdog → перезапуск; восстановление по D29 (identity-matched записи возобновляются, G1; ограничение владения документировано).

### s2-notifications (wave 1)

**Files:** Create: `NoHalla/Core/Notifications/NotificationCoordinator.swift`.
**dependsOn:** S1 APPROVED (NotificationEvent/Kind из ProtectionEngine). **writeScope:** `NoHalla/Core/Notifications/`.
**Interfaces / Produces:** `protocol NotificationCoordinating: AnyObject { func requestPermission() async; func setEnabled(_ enabled: Bool); func post(_ event: NotificationEvent); var onResumeAllAction: (() -> Void)?; func isPermissionDenied() async -> Bool }`; `final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, NotificationCoordinating` — категории FROZEN/RESUMED/UNKNOWN, action RESUME_ALL (foreground), throttle ≤1 уведомления каждого типа за 30 с, строки `notification.*` через L10n (без lore вместо причины), permission после онбординга (не на старте), denied → флаг для баннера General (ссылка `x-apple.systempreferences:com.apple.Notifications-Settings.extension`).
**Steps:**
- [ ] Реализовать по брифу §8.6/FR-29.
- [ ] Сборка — exit 0. Commit `feat: add local notification coordinator`.
**Acceptance:** компилируется; категории/action/throttle/permission-семантика; toggle учитывается.

### s2-controller (wave 2)

**Files:** Create: `NoHalla/Core/Process/ProcessController.swift`.
**dependsOn:** s2-enumerator, s2-safety. **writeScope:** `NoHalla/Core/Process/ProcessController.swift`.
**Interfaces / Produces:** `final class ProcessController: ProcessControlling` — `init(selfPID: Int32 = getpid(), watchdogPIDProvider: @escaping () -> Int32?)`; последовательное исполнение (serial queue/actor internals); freeze: enumerator-множество (instances+children+path-prefix) → SafetyGuard.isDenied/isInsideBundle → identity-check (startTime) → `kill(pid, SIGSTOP)`; идемпотентно (`Set<Int32>`); ESRCH → удалить из трекинга; EPERM → пропуск+лог; resumeAll: SIGCONT с той же identity-check; reconcile: добавить новые экземпляры/helpers, убрать завершившиеся (FR-24); возвращает актуальный `[FrozenProcess]` для StateStore.
**Steps:**
- [ ] Реализовать FR-18/19/20/24/45/46 + §8.4 (константы SIGSTOP/SIGCONT из Darwin).
- [ ] Сборка — exit 0. Commit `feat: add sigstop sigcont process controller`.
**Acceptance:** компилируется; Review Focus 1/2 закреплены (identity перед каждым сигналом, deny-list, path-prefix, uid); последовательность; ESRCH/EPERM явно; без двойных сигналов; журнал и восстановление по D29 (pre-write intent сохраняется; перенос записи после SIGSTOP запрещён; ограничение владения — принятое продуктовое решение, не дефект).

### s2-lifecycle (wave 2)

**Files:** Modify: `NoHalla/App/NoHallaAppDelegate.swift`; Create: `NoHalla/UI/Components/QuitConfirmationAlert.swift`.
**dependsOn:** s2-watchdog, S1 engine. **writeScope:** `NoHalla/App/NoHallaAppDelegate.swift`, `NoHalla/UI/Components/QuitConfirmationAlert.swift`.
**Interfaces / Produces:** `enum QuitConfirmationAlert { static func confirm(frozenCount: Int) async -> Bool }` — NSAlert, строки `quit.title`/`quit.body` (%d)/`quit.confirm` + Cancel (нативный порядок кнопок). AppDelegate: single-instance flock + активация первого (FR-43); startup: ConfigStore.load → engine.recoverStaleFrozen → WatchdogLauncher.start → engine.start (FR-6); `applicationShouldTerminate`: если frozen непуст → confirm → engine.stop (resume all + clear) → watchdog.stop → terminate; без frozen — без диалога (D20); SIGTERM/SIGINT DispatchSource → тот же путь (FR-5).
**Steps:**
- [ ] Реализовать lifecycle по FR-1/4/5/6/43; порядок recovery→watchdog→engine.
- [ ] Сборка — exit 0. Commit `feat: add quit flow and crash recovery lifecycle`.
**Acceptance:** компилируется; Review Focus 3 закреплен (quit/SIGTERM/SIGINT resume all + clear + watchdog stop; startup recovery; single instance).

### s2-wiring (integration, Integrator, после W2)

**Files:** Modify: `NoHalla/App/NoHallaApp.swift`, `NoHalla/App/AppState.swift`, `NoHalla/Core/Engine/ProtectionEngine.swift` (инъекции); Delete: `NoHalla/Core/Process/LoggingProcessController.swift`.
**writeScope:** `NoHalla/App/`, `NoHalla/Core/Engine/ProtectionEngine.swift`, `NoHalla/Core/Process/LoggingProcessController.swift` (удаление), `project.yml`.
**Steps:**
- [ ] Инжектировать реальный `ProcessController` (watchdogPIDProvider → launcher) вместо LoggingProcessController; удалить шов-файл.
- [ ] Wire `engine.onNotification` → NotificationCoordinator.post; coordinator.onResumeAllAction → engine.handle(.resumeAll); AppState.requestNotificationPermission → coordinator.requestPermission; denied → AppState.notificationsDenied (баннер General).
- [ ] Watchdog start/stop в AppDelegate согласован с engine.stop (порядок: resume→clear→watchdog.stop).
- [ ] verificationChecks S2 (пп.1–2, 4); исправить; snapshot + REVIEW_REQUEST S2.
- [ ] Commit `feat: wire real process control and notifications`.
**Acceptance S2:** сборка зелёная; полный путь freeze/resume/watchdog/recovery/notification wired; шов S1 удалён; FR-15…25/41…46 реализованы.

---

## Stage S3 — UI по дизайну + бренд + доки (M5+M6)

Общее для UI-задач: источник пикселей — Doop-канвас через doop MCP (`doop_get_frame`/`doop_get_frame_screenshot`, canvas `2lgrE5QsCb`) + `design/HANDOFF.md` (frame id → view) + офлайн-макеты `design/mockups/*.html` (fallback, D4); Dark — первичный референс, Light — адаптация, Increase Contrast — третий вариант tokens.json. Компоненты — s3-components; строки — L10n (ключи copy.json); токены — DesignTokens; нативные контролы, без кастомных шрифтов/фонов; a11y — design/ACCESSIBILITY.md (фокус, VoiceOver, 28 pt targets, контраст); Previews с моковыми состояниями обязательны.

### s3-components (wave 1)

**Files:** Create: `NoHalla/UI/Components/StatusPillView.swift`, `AppRowView.swift`, `GateRuleView.swift`, `GateSceneView.swift`, `NetworkCardView.swift`, `CountdownBarView.swift`, `SettingRowView.swift` (+прочие общие компоненты по design/COMPONENTS.md, кроме QuitConfirmationAlert).
**dependsOn:** S2 APPROVED. **writeScope:** `NoHalla/UI/Components/` (кроме QuitConfirmationAlert.swift).
**Interfaces / Produces:** `StatusPillView(status: UIStatus)` (глиф+семантический текст+бронзовый ободок 1 pt, высота 22, radius 11, wrap длинных переводов); `AppRowView(app: ProtectedApp, runState: AppRunState, isFrozen: Bool, onToggle: (Bool) -> Void)` (`enum AppRunState { case active, frozen, notRunning }` — определить здесь); 44 pt строка, иконка 20 pt (NSWorkspace), frozen rim 1 pt, toggle-label включает имя; `GateRuleView()` (1 pt бронза, 24 штриха, accessibilityHidden); `GateSceneView(variant: GateSceneVariant)` (`enum GateSceneVariant { case hero, about, empty }`, декор, SVG-ассет); `NetworkCardView(ipv4: String?, ipv6: String?, vpnInterface: String?, trusted: Bool, onAddCurrentIP: (() -> Void)?, onRefresh: (() -> Void)?)` (mono IP, label-pairs читаются вместе); `CountdownBarView(remaining: Int, total: Int)` (линейный бар+текст, Reduce Motion → snap); `SettingRowView` (label lane + trailing control + helper text).
**Steps:**
- [ ] Реализовать варианты/состояния по COMPONENTS.md; нативные стили кнопок (blue Resume all, destructive только Reset, target ≥28 pt).
- [ ] A11y-лейблы и фокус; Previews всех вариантов; сборка — exit 0.
- [ ] Commit `feat: add shared ui components per design`.
**Acceptance:** компилируется; варианты COMPONENTS.md покрыты; бронза не несёт смысла статуса; Previews есть.

### s3-diagnostics (wave 1)

**Files:** Create: `NoHalla/Core/Diagnostics/DiagnosticsExporter.swift`.
**dependsOn:** S1 APPROVED. **writeScope:** `NoHalla/Core/Diagnostics/`.
**Interfaces / Produces:** `enum DiagnosticsExporter { static func export(to url: URL, configDirectory: URL) throws }` — собирает config.json, state.json, логи последних 15 минут (OSLogStore(scope: .currentProcessIdentifier), best-effort: при пустом/недоступном — пометка в export-notes), versions.txt (macOS + No-halla 0.9.0); ZIP через `/usr/bin/zip` (Process); без автоматической отправки (FR-32).
**Steps:**
- [ ] Реализовать; NSSavePanel вызывает UI (s3-settings-advanced), экспортёр принимает готовый URL.
- [ ] Сборка — exit 0. Commit `feat: add local diagnostics zip export`.
**Acceptance:** компилируется; состав ZIP по FR-32; неполные логи помечаются (spec риск OSLogStore).

### s3-popover (wave 2)

**Files:** Modify: `NoHalla/UI/Popover/PopoverView.swift` (заменить placeholder S1); Create: подвиды в `NoHalla/UI/Popover/`.
**dependsOn:** s3-components, s3-apppicker. **writeScope:** `NoHalla/UI/Popover/`.
**Interfaces / Consumes:** AppState.snapshot/config, компоненты s3, L10n, DesignTokens; действия → AppState → engine.handle.
**Steps:**
- [ ] Полный поповер 360 pt по дизайн §7.2/HANDOFF (все кадры Popover · *): header (No-halla + StatusPill + lore 11 pt фикс-высота) + GateRule; NetworkCard (unknown → `—` + «Can't verify IP»; Add current IP если не доверенный); Protected apps (AppRow, toggle, empty state «No one is guarding the gate yet» + Choose apps → picker); primary action по состоянию (protected→Pause меню 15/60/until relaunch; grace→Freeze now + Cancel (D25) + CountdownBar; frozen→Resume all + caption.resumeBypass (%d); unknown→Retry + Resume all; paused→Turn on now + время; disabled→Turn on (D27); setup→Add current IP; bypassing→статус Bypassing until HH:mm + возврат защиты); footer Settings/Quit (Quit → QuitConfirmationAlert если frozen).
- [ ] Без скролла при 0–4 приложениях, дальше — скролл только списка; RU grace frame не обрезается; фокус-порядок ACCESSIBILITY; Esc best-effort (D23); Previews всех состояний.
- [ ] Сборка — exit 0. Commit `feat: add full popover for all protection states`.
**Acceptance:** компилируется; все состояния HANDOFF реализованы; FR-21/22/23/25/26 UI-поведение; a11y-порядок.

### s3-onboarding (wave 2)

**Files:** Create: `NoHalla/UI/Onboarding/OnboardingContainerView.swift`, `OnboardingIntroView.swift`, `OnboardingAppsView.swift`, `OnboardingTrustedRealmView.swift`.
**dependsOn:** s3-components. **writeScope:** `NoHalla/UI/Onboarding/`.
**Steps:**
- [ ] 3 шага 560×420 по дизайн §7.3/HANDOFF: intro (GateScene.hero, hero-заголовок 22–24 pt, Continue/Skip setup → пустое состояние); apps (запущенные с чекбоксами+поиск, предложения Claude/Cursor/ChatGPT только если запущены — NSWorkspace-проверка bundle ID брифа §13, Add other app… → NSOpenPanel, счётчик %d, Back/Continue); trusted realm (текущий IP крупно, Trust this IP / Add manually с CIDR-валидацией inline, toggle Launch at login default on → SMAppService, Back/Finish); прогресс-точки; Finish → onboardingCompleted=true + NotificationCoordinator.requestPermission.
- [ ] Окно показывается при !onboardingCompleted (scene wiring — s3-final); Previews шагов; сборка — exit 0.
- [ ] Commit `feat: add three step onboarding flow`.
**Acceptance:** компилируется; ровно 3 шага; FR-2/3/10; валидация IP; permission после Finish.

### s3-settings-general (wave 2)

**Files:** Create: `NoHalla/UI/Settings/SettingsGeneralView.swift`, `SettingsAboutView.swift`.
**dependsOn:** s3-components. **writeScope:** `NoHalla/UI/Settings/SettingsGeneralView.swift`, `SettingsAboutView.swift`.
**Steps:**
- [ ] General: Launch at login toggle + inline-ошибка SMAppService (статус синхронизирован с фактическим), Notifications toggle + denied-баннер «Open System Settings» (AppState.notificationsDenied), Language System/English/Русский + «Apply language change» (L10n in-process, D12); баннер битого конфига (FR-38, ключи D22).
- [ ] About: AppIcon, No-halla, tagline, версия 0.9.0 (параметризованный ключ), «Free and open source. MIT License.», Copy version info, GateRule/GateScene.about; строка Repository СКРЫТА (D26).
- [ ] Previews; сборка — exit 0. Commit `feat: add settings general and about tabs`.
**Acceptance:** компилируется; дизайн §7.4 General/About; FR-3/27/29/33; inline-ошибки без модалок.

### s3-settings-protection (wave 2)

**Files:** Create: `NoHalla/UI/Settings/SettingsProtectionView.swift`, `TrustedAddressEditor.swift`.
**dependsOn:** s3-components. **writeScope:** `NoHalla/UI/Settings/SettingsProtectionView.swift`, `TrustedAddressEditor.swift`.
**Steps:**
- [ ] Master-переключатель «Защита» в начале (D27): off → engine.setProtectionEnabled(false) (resume all + disabled), on → checking; новые строки D22.
- [ ] Grace slider 0–120 с default 5 (D24) + helper; Check interval 10–120 default 30 (D19); Freeze when unknown / Check IPv6 / Require VPN interface toggles + пояснения; Trusted IPs список add/remove/edit (TrustedAddressEditor sheet: CIDR-валидация inline, невалидное не сохраняется) + Add current IP; Protected apps список add/remove (Add → AppPickerSheet) со статусом running/not running.
- [ ] Previews; сборка — exit 0. Commit `feat: add protection settings tab and ip editor`.
**Acceptance:** компилируется; дизайн §7.4 Protection + D24/D27; валидации inline; изменения применяются к engine/config немедленно.

### s3-settings-advanced (wave 2)

**Files:** Create: `NoHalla/UI/Settings/SettingsAdvancedView.swift`, `EndpointEditor.swift`, `ResetSettingsAlert.swift`.
**dependsOn:** s3-components, s3-diagnostics. **writeScope:** `NoHalla/UI/Settings/SettingsAdvancedView.swift`, `EndpointEditor.swift`, `ResetSettingsAlert.swift`.
**Steps:**
- [ ] Endpoints v4/v6 списки: edit (EndpointEditor sheet, HTTPS-валидация «Use an HTTPS endpoint that returns an IP address»), reset to defaults; Manual resume bypass 0–60 мин default 5; Log level Info/Debug (D11, ключи D22); Export diagnostics… → NSSavePanel → DiagnosticsExporter.export; Reset all settings… destructive + ResetSettingsAlert (подтверждение, строки ui.reset-settings/ui.frozen-apps-will-resume…) → AppConfig.defaults + engine.configChanged.
- [ ] Previews; сборка — exit 0. Commit `feat: add advanced settings and endpoint editor`.
**Acceptance:** компилируется; дизайн §7.4 Advanced; FR-8/22/27/32; destructive только Reset.

### s3-apppicker (wave 1)

**Files:** Create: `NoHalla/UI/AppPicker/AppPickerSheet.swift`.
**dependsOn:** s3-components, s2-safety. **writeScope:** `NoHalla/UI/AppPicker/`.
**Steps:**
- [ ] Sheet 480×520 по дизайн §7.5/HANDOFF: заголовок Add apps, поиск (имя+bundle ID), группы Running (NSWorkspace) и Applications (/Applications scan), строки иконка/имя/bundle ID мелко/чекбокс, уже добавленные disabled «Added», системные/Terminal-подобные — жёлтое предупреждение (SafetyGuard.pickerWarning, a11y-объяснение недоступности), Cancel/Add (disabled без выбора), Add other app → NSOpenPanel; запрет дублей (FR-28).
- [ ] Previews (empty/typing/no-matches/warning); сборка — exit 0. Commit `feat: add app picker sheet with warnings`.
**Acceptance:** компилируется; FR-15/17/28; предупреждения и disabled-причины доступны a11y.

### s3-final (integration, Integrator, после W2)

**Files:** Modify: `NoHalla/App/NoHallaApp.swift`, `AppState.swift`, `NoHallaAppDelegate.swift` (финальные сцены), `design/copy.json` + `Localizable.xcstrings` (обнаруженные недостающие ключи,regen), `design/OPEN_QUESTIONS.md` (закрыто решениями D24–D28), Orca pod memory (append); Create: `NoHalla/UI/Settings/SettingsRootView.swift`, `README.md`, `LICENSE`.
**writeScope:** `NoHalla/App/`, `NoHalla/UI/Settings/SettingsRootView.swift`, `README.md`, `LICENSE`, Orca pod memory, `design/OPEN_QUESTIONS.md`, `design/copy.json`, `NoHalla/Resources/Localizable.xcstrings`, `project.yml`.
**Steps:**
- [ ] SettingsRootView: TabView 4 вкладки (General/Protection/Advanced/About), toolbar иконка+текст, бронзовое подчёркивание выбранной (COMPONENTS.md), окно 680×520.
- [ ] Сцены: Settings { SettingsRootView }, Window(id "onboarding") при !onboardingCompleted, MenuBarExtra → полный PopoverView; AppState финальный (баннеры, действия, язык); menu bar VoiceOver-лейблы ACCESSIBILITY.
- [ ] A11y-проход по всем экранам (фокус/Esc/contrast/reduce motion/transparency); Previews полны; недостающие строки — аддитивно в copy.json + regen (D22).
- [ ] Orca pod memory: все отклонения (D2 тесты/test-target'ы, D9 ассеты, D11 logLevel, D12 язык, D13 layout, D14 zip/OSLogStore, D16 .gitignore, D22 новые строки, D23 Esc, D24 grace 120, D26 repo hidden, D27 master toggle, D28 IPv6, **D29 восстановление: identity-checked intent recovery, G1 приоритет, узкий остаточный риск G2 принят владельцем — со ссылкой на C2-guarantee-conflict.md и блиц ревизии**) с обоснованиями.
- [ ] README.md по брифу §4: название/tagline, что делает/чем не является (SIGSTOP ≠ firewall), требования, сборка/запуск, автозапуск, troubleshooting (`kill -CONT <pid>`, Activity Monitor), удаление (+снятие автозапуска), лицензия, **ограничение владения восстановлением (D29): в узком окне аварии восстановление может снять паузу, поставленную другим инструментом на защищённое приложение; экспозиция сужена SafetyGuard; для строгой изоляции остановок не использовать сторонние паузы на защищённых приложениях**, **чеклист ручной матрицы 20 сценариев (бриф §9) для владельца** + отметка «тесты исключены решением владельца; первый запуск — вручную». LICENSE MIT.
- [ ] Кумулятивные verificationChecks (пп.1–8); исправить всё, что они сообщают.
- [ ] Commit `docs: add readme license and decisions log` (+ отдельные логические коммиты wiring).
- [ ] Snapshot + REVIEW_REQUEST S3 (final stage marker, кумулятивный список TODO→files, baseline, checks с exit-кодами и output-ссылками, affected consumers, planned diagnostics Reviewer'а).
**Acceptance S3 / Definition of Done (spec §11):** все 10 пунктов; ручная матрица и runtime-проверки — чеклист владельца (D6).

---

## Self-review плана (выполнен Planner'ом)

1. **Spec coverage:** D1–D28 → задачи: D5 стадии; D6 checks; D7/D8 s1-engine/s1-seam/s2-controller; D9 s1-assets; D10/D22 s1-strings/s3-final; D11 s1-models/s3-settings-advanced; D12 s1-strings/s3-settings-general; D13 s2-notifications; D14 s3-diagnostics; D15 s2-lifecycle; D16 s1-scaffold; D17 s1-scaffold; D18 s1-wiring; D19 s1-models/s3-settings-protection; D20 s2-lifecycle; D21 s3-final; D24 s1-models/s3-settings-protection; D25 s1-statemachine/s3-popover; D26 s3-settings-general; D27 s1-statemachine/s3-settings-protection; D28 s1-engine. FR-1…46 покрыты (жизненный цикл S1/S2, сеть S1, процессы S2, UI S3, бренд S1/S3, конфиг S1, надёжность S2). Гэпов нет.
2. **Step scan:** шаги однозначны (сигнатуры/значения закреплены, тела — строителю); test-шагов нет (D2).
3. **Type consistency:** ProcessControlling, EngineSnapshot, NotificationEvent/Kind, UIStatus, AppRunState, FamilyResult — определены один раз и потребляются по именам; s1-models пишет против контракта s1-cidr (явно указано); AppState-поверхность (send/setConfig/requestNotificationPermission/баннеры) закреплена в s1-wiring/s2-wiring до UI-задач S3.
4. **Review Focus:** 5 режимов закреплены в acceptance владеющих задач (s2-controller, s2-safety, s2-watchdog/s2-lifecycle/s1-engine, s1-ipverify/s1-engine, s1-netmon/s1-engine/s2-controller).
5. **Proportion:** план — контракты и решения, не транскрипт кода; тела алгоритмов не выписаны (кроме нормативных таблиц брифа).
6. **Исправлено cross-review'ом:** скрытые зависимости параллельных задач устранены (s1-strings → W2 после s1-models; menuBarImageName перенесён в s1-wiring; s3-apppicker → W1 до потребителей; SettingsRootView → s3-final после всех вкладок); устарелые T-id в Review Focus заменены на todoId; пик параллельности 5.
7. **Ревизия C2 (plan-v2):** затронуты только s2-controller, s2-watchdog, s1-engine (recoverStaleFrozen) + документация s3-final; семантика восстановления закреплена spec D29 (вариант D, ответ владельца в блице ревизии); код на HEAD 381e613 уже соответствует D29 — дельта ревизии преимущественно документационная; остальной план и реестр без изменений; self-review против spec-v2 пройден (покрытие D29 во всех затронутых TODO, типы не менялись, test-шагов нет).