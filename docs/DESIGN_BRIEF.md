# Бриф для дизайн-агента: No-halla — per-app kill switch для macOS

> **Как использовать.** Передай этот файл целиком дизайн-агенту (Qoder / Claude / GPT) в пустой репозиторий. Результат работы — папка `design/` с артефактами из раздела 12. Кодинг-агент реализует приложение по `IMPLEMENTATION_BRIEF.md`, используя `design/` как источник правды по интерфейсу, текстам и визуалу.
>
> **Роль.** Ты — senior product designer с опытом macOS HIG, menu bar приложений и privacy-инструментов. Ты не пишешь production-код приложения. Ты проектируешь экраны, состояния, взаимодействия, тексты, иконки и передаёшь спецификацию в виде макетов и токенов.
>
> **Визуальный приоритет — dark-first.** Тёмная тема — герой и первичный референс. Бренд-мир (фьорд / бронза / ворота) живёт внутри нативной оболочки, а не только в иконке и About. Светлая тема — полноценная адаптация. Нативные контролы, ясность статуса и доступность неприкосновенны. См. раздел 10.

---

## 1. Продукт

**No-halla** — бесплатный open-source аналог [kordon](https://github.com/ef1m03/kordon) для macOS. Название — игра слов с Valhalla: «Вальхалла подождёт». Приложения не «возносятся» в открытый интернет, пока VPN не вернётся; они ждут у ворот.

**Tagline:** «Valhalla can wait.» / «Вальхалла подождёт.»

### 1.1. Что делает

1. Следит за внешним IP-адресом и сетевыми изменениями.
2. Если IP перестал быть доверенным (VPN упал, сменилась сеть, туннель переподключился) — через короткий grace-период **замораживает выбранные пользователем приложения** (`SIGSTOP`), а не отключает интернет целиком.
3. Когда доверенный IP возвращается — **возобновляет** приложения (`SIGCONT`).
4. Всегда показывает, что происходит, и даёт возобновить всё одним действием.

### 1.2. Чего продукт не делает (v1)

- Не является VPN-клиентом и не настраивает VPN.
- Не блокирует трафик системно (никаких `pf`, Network Extension, файрвола).
- Не защищает все приложения сразу — только выбранный список.
- Не поддерживает Windows и Linux.
- Не имеет аккаунтов, облака, аналитики, телеметрии, автообновления.

### 1.3. Метафора и словарь

Скандинавская тема — это **слой истории**, а не смена парадигмы интерфейса. Функциональные подписи остаются предельно ясными; лор живёт в поддерживающих строках, иллюстрациях, названиях состояний и уведомлениях.

| Образ | Значение в продукте |
|---|---|
| Ворота (the gate) | VPN-туннель, точка выхода в интернет |
| Доверенный мир (trusted realm) | доверенные IP/CIDR |
| Ворота открыты (the gate is open) | трафик разрешён: IP доверенный, защита на паузе или выключена |
| Ворота закрыты (the gate is closed) | приложения заморожены: IP недоверенный или не подтверждён |
| Ворота приоткрыты (the gate is ajar) | ручной обход: заморозка снята до конца окна |
| Ждут у ворот (waiting at the gate) | образ для онбординга и уведомлений: приложения заморожены |
| Стража (the watch) | сам No-halla и его фоновый watchdog |

Правила словаря:

- «No-halla» всегда с заглавной N и дефисом.
- Не использовать слова «death», «kill», «sacrifice», «warrior» в UI.
- Не называть приложения «воинами» и не обыгрывать смерть — только ворота, стража, ожидание.
- Функциональные термины (`Frozen`, `IP`, `VPN`, `Resume all`) не заменять метафорами.

### 1.4. Почему это нужно

Пользователь работает через VPN и использует приложения, которые не должны «светить» реальный IP (Claude Desktop, Cursor, ChatGPT и подобные). При обрыве VPN эти приложения могут продолжить отправлять запросы напрямую. Полный kill switch неудобен: он рубит весь интернет. No-halla ставит на паузу только выбранные приложения и возвращает их, когда VPN снова в строю.

---

## 2. Пользователь и сценарии

### Primary persona

Разработчик или фрилансер, 25–45 лет, macOS 13+, работает через VPN (корпоративный WireGuard/OpenVPN, Amnezia, Tailscale и т.п.). В день использует Claude Desktop, Cursor, ChatGPT, браузер. Технически грамотный, но не хочет каждый раз вручную проверять IP и закрывать приложения. Ценит прозрачность и контроль, не любит «магию» и тревожные интерфейсы. Скандинавская эстетика ему скорее нравится, но он не хочет, чтобы она мешала работе.

### Jobs to be done

- «Когда VPN падает, не дай моим AI-инструментам отправить запрос с реального IP».
- «Покажи за секунду, защищён я сейчас или нет».
- «Если что-то замерло — дай вернуть это одним кликом и объясни, почему».
- «Не трогай приложения, которые я не выбирал».

### Ключевые сценарии

1. Первый запуск: понять, что делает приложение, выбрать 2–3 приложения, добавить текущий IP в доверенные, включить автозапуск.
2. Обычный день: VPN включён, IP доверенный, статус «Protected», всё работает.
3. Обрыв VPN: появляется grace-отсчёт, приложения замораживаются, приходит уведомление. Пользователь видит причину и может возобновить вручную.
4. VPN вернулся: приложения автоматически возобновляются, приходит уведомление.
5. Пользователь сам выключил VPN и хочет поработать: ставит защиту на паузу на 15 минут / час / до перезапуска.
6. Ложное срабатывание: пользователь добавляет текущий IP в доверенные или жмёт «Resume all».

---

## 3. Принципы дизайна

1. **Native macOS first.** SF Pro, системные контролы (`Form`/`List`/`MenuBarExtra`), vibrancy, стандартные отступы и размеры. Никакого «веб-приложения в окне» и никаких кастомных рамок. Нативный каркас несёт бренд-слой, но не подменяется им.
2. **Статус понятен за одну секунду.** Иконка в menu bar и заголовок поповера отвечают на вопрос «я защищён?» без открытия настроек.
3. **Dark-first brand shell.** Тёмная тема — первичная цель дизайна и герой макетов: фьордовая тонированная оболочка, бронза как акцент идентичности. Светлая — полноценная адаптация той же структуры. Приложение следует системной теме, не форсирует тёмную.
4. **Calm tech, not bare tech.** Спокойно, но не голо: тональная глубина, бронзовые детали, орнамент. Без тревожности, восклицательных знаков, красных кнопок для безопасных действий и анимаций-вспышек.
5. **Lore in the shell.** Скандинавская тема живёт в оболочке (шапка, линия ворот, ободок статуса), иконке, иллюстрациях, пустых состояниях, уведомлениях и About. Функциональные подписи контролов и статусов остаются ясными; лор не заменяет их.
6. **Прозрачность.** Всегда видно: текущий IP, доверенный ли он, какие приложения заморожены, сколько осталось до заморозки и что произойдёт дальше.
7. **Возврат управления в один клик.** «Resume all» доступен из поповера, уведомления и диалога выхода. Никогда не прячь его.
8. **Privacy by design.** Ноль аккаунтов и аналитики. Интерфейс не создаёт ощущение слежки.

---

## 4. Границы дизайна

### In scope

- Menu bar иконка (5 состояний).
- Поповер — главный экран.
- Онбординг из 3 шагов.
- Окно настроек: 4 вкладки (General, Protection, Advanced, About).
- Шит выбора приложений.
- Уведомления (3 типа) и диалог подтверждения выхода.
- Пустые состояния и ошибки.
- Тёмная (dark-first, первичная) и светлая темы, Increase Contrast, Reduce Transparency, Reduce Motion.
- Локализация EN + RU (English — базовый, русский — второй).
- Бренд-слой: иконка приложения, menu bar glyph, иллюстрации, tagline, словарь.

### Out of scope

- Экраны VPN-подключения, карта серверов, графики трафика.
- Дашборды, статистика, история IP.
- Настройки системного файрвола.
- Мобильные и десктопные версии для других ОС.
- Маркетинговый сайт и App Store-скриншоты.
- Любые фичи, которых нет в этом документе. Если без них не обойтись — запиши в `design/OPEN_QUESTIONS.md` с рекомендацией, но не рисуй.

---

## 5. Информационная архитектура

```
Menu bar icon
└── Popover (главный экран)
    ├── Header: No-halla + статус + lore-подпись
    ├── Network card: текущий IP, VPN-интерфейс, доверенность
    ├── Protected apps: список приложений
    ├── Primary action (контекстное)
    └── Footer: Settings, Quit
        │
        ├── Settings window
        │   ├── General
        │   ├── Protection
        │   ├── Advanced
        │   └── About
        └── Sheets
            ├── App picker
            └── Quit confirmation

Onboarding window (первый запуск, 3 шага)
Notifications (Frozen / Resumed / Can't verify IP)
```

---

## 6. Модель состояний

| Состояние | Значение | Иконка menu bar | Пилюля статуса | Lore-подпись | Главное действие |
|---|---|---|---|---|---|
| `checking` | Идёт первая/очередная проверка IP | shield + spinner | Checking… | Testing the gate. | нет (disabled) |
| `protected` | IP доверенный, приложения активны | shield | Protected | The gate is open. | Pause |
| `grace` | IP недоверенный, идёт отсчёт до заморозки | shield + clock | VPN lost — freezing in Ns | The gate is closing. | Freeze now |
| `frozen` | Приложения заморожены | pause.circle | Frozen | The gate is closed. | Resume all |
| `unknown` | Не удалось проверить IP (нет кворума) | exclamationmark.shield | Can't verify IP | The gate doesn't answer. | Retry / Resume all |
| `paused` | Защита на паузе по команде пользователя | shield.slash | Protection off until 14:32 | The gate is open. | Turn on now |
| `disabled` | Защита выключена в настройках | shield.slash | Protection off | The gate is open. | Turn on |
| `setup` | Не настроен ни один доверенный IP | exclamationmark.shield | Set up trusted IP | No trusted realm yet. | Add current IP |

Дополнительно:

- **Bypass после ручного Resume all**: статус `protected` не показываем; показываем `Bypassing until 14:37` с lore-подписью `The gate is ajar.` и возможностью вернуть защиту.
- **Нет выбранных приложений**: защита формально включена, но работать нечему — показываем empty state с CTA «Choose apps».
- **Приложение не запущено**: строка в списке показывает `Not running`, но остаётся в конфиге.

Lore-подписи — вспомогательные. Пилюля статуса всегда содержит функциональный текст; lore-подпись не заменяет его и не показывается в уведомлениях вместо причины.

---

## 7. Экраны

### 7.1 Menu bar icon

- Template image 18×18 pt (PDF/SVG), монохромная, автоматически адаптируется к тёмной/светлой панели.
- Форма: **круглый скандинавский щит** с центральным умбоном и двумя вертикальными полосами паузы. Читается на 18 px, не выглядит как логотип мебельной компании.
- 5 визуально различимых состояний: `protected`, `checking/grace`, `frozen`, `unknown/setup`, `paused/disabled`.
- Допустимо использовать SF Symbols как основу для внутренних экранов, но menu bar — отдельный SVG.
- Никаких рун внутри 18-пиксельного глифа: они превращаются в грязь. Рунический орнамент — в иконке приложения, иллюстрациях и орнаменте оболочки (линия ворот, разделители), но не в menu bar глифе.

ASCII-подсказка (не финальный вид):

```
protected   checking/grace   frozen   unknown   off
  [◈]          [◈◷]          [❚❚]     [!◈]     [◈/]
```

### 7.2 Поповер (360 pt ширина)

Стиль: `MenuBarExtra` + `.menuBarExtraStyle(.window)`, системный material, скругление системное.

Тёмная тема — референс. Оболочка тонирована фьордом (фон `#0E1F26`, группы `#1C333D`), не нейтрально-серая. Под шапкой — бронзовая «линия ворот» (1 pt, орнамент из 24 штрихов — мотив иконки). Статус-пилюля несёт тонкий бронзовый ободок (декор, не смысл статуса); цвет статуса остаётся семантическим. Контролы нативные, плоские. Светлая тема повторяет структуру с более светлой оболочкой.

```
┌──────────────────────────────────────────────┐
│ No-halla                        [ Protected ]│
│ The gate is open.                            │
│                                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Current IP        203.0.113.5      [↻]   │ │
│ │ VPN interface     utun3                  │ │
│ │ Trusted           Yes                    │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ Protected apps                    + Add app  │
│ ┌──────────────────────────────────────────┐ │
│ │ [icon] Claude          Active       [●]  │ │
│ │ [icon] Cursor          Frozen       [●]  │ │
│ │ [icon] ChatGPT         Not running  [●]  │ │
│ └──────────────────────────────────────────┘ │
│                                              │
│ [        Primary action (full width)       ] │
│  caption под кнопкой                         │
│                                              │
│ ⚙ Settings                            Quit   │
└──────────────────────────────────────────────┘
```

Обязательные элементы и правила:

1. **Header.** «No-halla» слева, статус-пилюля справа. Под именем/пилюлей — lore-подпись из таблицы состояний, 11 pt secondary. Пилюля = иконка + текст, не только цвет, с тонким бронзовым ободком. Под шапкой — бронзовая линия ворот; она не меняет высоту header и не заменяет статус.
2. **Network card.**
   - Текущий IP моноширинным шрифтом.
   - VPN-интерфейс (`utun3`, `ipsec0`, `—`), если определён.
   - `Trusted: Yes / No`.
   - Кнопка «Add current IP» показывается, если IP не доверенный.
   - При `unknown` вместо IP — `—` и подпись «Can't verify IP».
3. **Protected apps.**
   - Каждая строка: иконка приложения, имя, статус (`Active`, `Frozen`, `Not running`), toggle.
   - Toggle выключает защиту конкретного приложения, не удаляя его.
   - Заголовок секции + ссылка `+ Add app`.
   - Если пусто — empty state: «No one is guarding the gate yet» + кнопка «Choose apps».
4. **Primary action** зависит от состояния:
   - `protected` → secondary «Pause» (меню: 15 minutes / 1 hour / Until relaunch).
   - `grace` → большая кнопка «Freeze now» + ссылка «Cancel»; рядом/внутри — кольцевой или линейный countdown.
   - `frozen` → primary «Resume all», caption «Apps will unfreeze for 5 minutes, then protection resumes.»
   - `unknown` → «Retry» + secondary «Resume all».
   - `paused` → «Turn on now» + caption с временем окончания паузы.
   - `setup` → «Add current IP».
5. **Footer.** Шестерёнка (Settings) слева, «Quit» справа. Quit при замороженных приложениях открывает подтверждение.
6. **Высота.** Поповер не должен скроллиться при 0–4 приложениях; при большем количестве — скролл только внутри списка приложений.
7. **Lore-подпись** не должна прыгать по высоте: резервируй одну строку или используй фиксированную высоту header.

### 7.3 Онбординг (560×420, 3 шага)

**Шаг 1 — The gate.**
- Заголовок: «Keep the gate closed when the VPN falls». Hero-заголовок: SF Pro Display 22–24 pt semibold.
- Короткое объяснение: «No-halla watches your IP. If it leaves the trusted realm, selected apps wait at the gate and blocked sites stop resolving until your VPN returns.»
- Иллюстрация (hero): геометрические ворота/щит на горизонте фьорда, 1.5 px line art, бронза/кость на фьорде, тональный фьорд-градиент фона, слоистая глубина (дальний хребет + ворота). Без лиц, оружия, черепов и «викингских» клише.
- Кнопки: `Continue` (primary), `Skip setup` (tertiary, ведёт к пустому состоянию).

**Шаг 2 — Choose apps.**
- Заголовок: «Choose who waits at the gate».
- Список запущенных приложений с чекбоксами; сверху поиск.
- Предложения по умолчанию, если запущены: Claude, Cursor, ChatGPT.
- Кнопка `Add other app…` открывает `NSOpenPanel` (в дизайне — просто кнопка).
- Счётчик выбранных: «2 apps selected».
- Кнопки: `Back`, `Continue`.

**Шаг 3 — Trusted realm.**
- Заголовок: «Trust your VPN's realm».
- Показывает определённый текущий IP крупно.
- Основное действие: «Trust this IP» (primary).
- Альтернатива: «Add manually» с полем IPv4/IPv6/CIDR и валидацией.
- Пояснение: «Only this IP opens the gate. Add your VPN IP here.»
- Toggle «Launch No-halla at login» (по умолчанию включён).
- Кнопки: `Back`, `Finish`.
- После Finish — системный запрос уведомлений (стандартный, не рисуем).

Прогресс: 3 точки или тонкая полоса сверху. Без анимаций-празднований. Разделитель между шагами может быть геометрическим орнаментом (SVG), не текстовыми рунами.

### 7.4 Настройки (680×520, 4 вкладки)

**General**
- Launch at login (toggle + inline error, если регистрация не удалась).
- Notifications (toggle).
- Language: System / English / Русский.

**Protection**
- Grace period: slider/stepper 0–60 s, default 5 s, с подписью «Apps freeze after this delay when the IP changes».
- Check interval: 10–120 s, default 30 s.
- Freeze when IP can't be verified (toggle, default on).
- Check IPv6 (toggle, default on).
- Require active VPN interface (advanced toggle, default off) + пояснение.
- Trusted IPs: список с add/remove/edit, валидация IPv4/IPv6/CIDR, кнопка «Add current IP».
- Protected apps: список с add/remove, статус running/not running.

**Advanced**
- IP check endpoints: список URL (v4 и v6), edit, reset to defaults.
- Manual resume bypass: 0–60 min, default 5.
- Log level: Info / Debug.
- Export diagnostics… (NSSavePanel).
- Reset all settings… (destructive, с подтверждением).

**About**
- Иконка приложения, название No-halla, tagline «Valhalla can wait.», версия. Допустим hero-заголовок 22–24 pt и малая фьорд-иллюстрация ворот.
- «Free and open source. MIT License.»
- Ссылка на репозиторий.
- Кнопка «Copy version info».
- Бронзовая линия ворот / геометрический рунический орнамент (SVG) как разделитель, не текстовая руна.

### 7.5 Шит выбора приложений (480×520)

- Заголовок «Add apps».
- Поиск.
- Две группы: `Running` и `Applications` (из `/Applications`).
- Каждая строка: иконка, имя, bundle ID мелким шрифтом, чекбокс.
- Уже добавленные — disabled с подписью `Added`.
- Системные/опасные приложения (Finder, Dock, Terminal, iTerm) — с жёлтой пометкой и пояснением, что заморозка может быть нежелательной.
- Кнопки: `Cancel`, `Add` (disabled, пока ничего не выбрано).

### 7.6 Уведомления

1. **Frozen**  
   Title: «The gate is closed»  
   Body: «Your IP changed to 203.0.113.5. Claude and Cursor are waiting at the gate until your VPN returns.»  
   Actions: `Resume all`, `Open No-halla`.
2. **Resumed**  
   Title: «The gate is open»  
   Body: «Trusted IP is back. Claude and Cursor are running again.»
3. **Can't verify IP**  
   Title: «The gate doesn't answer»  
   Body: «No-halla can't reach the IP check services. Protected apps will stay frozen until the check succeeds.»  
   Actions: `Retry`, `Resume all`.

Правила: без восклицательных знаков, без имён серверов, IP — только в Frozen (это объясняет причину). Не спамить: не чаще одного уведомления каждого типа за 30 секунд. Lore-заголовок допустим, но body всегда объясняет причину функционально.

### 7.7 Диалог выхода

Показывается, если есть замороженные приложения:

> **Quit No-halla?**  
> 3 frozen apps will be resumed. The gate will open and protection will stop until you launch No-halla again.  
> [Cancel] [Quit and Resume]

Если замороженных нет — выходить без диалога.

### 7.8 Пустые состояния и ошибки

Пустые состояния несут малую фьорд-иллюстрацию (line art, бронза/кость) над текстом — не голая строка. Иллюстрация декоративна и не заменяет CTA.

- **Нет приложений**: «No one is guarding the gate yet» + `Choose apps`.
- **Нет доверенных IP**: «No trusted realm yet. Protection can't start.» + `Add current IP`.
- **Нет сети**: «You're offline. The gate will be checked when the network is back.»
- **Все endpoint'ы недоступны**: «The gate doesn't answer.» + `Retry`, `Resume all`.
- **Нет разрешения на уведомления**: inline-баннер в General с кнопкой `Open System Settings`.
- **Ошибка автозапуска**: inline-ошибка под toggle, без модалок.

---

## 8. Взаимодействия и правила

| Действие | Поведение UI |
|---|---|
| Network change / IP change | Немедленная проверка; статус `checking`, затем `grace` или `protected` |
| Grace countdown | Тикает раз в секунду, отменяется при возврате доверенного IP; кнопка `Freeze now` замораживает сразу |
| Freeze | Статус `frozen`, уведомление, primary `Resume all` |
| Resume all (вручную) | Все приложения возобновляются, статус `Bypassing until HH:mm`, через 5 минут — повторная проверка и, если IP плохой, снова заморозка |
| Add current IP | IP добавляется в trusted, статус обновляется сразу, если приложения были заморожены — они возобновляются |
| Pause 15 min / 1 hour / Until relaunch | Все замороженные возобновляются, freeze отключён, в статусе время окончания; по истечении — немедленная проверка |
| Новый экземпляр приложения при `frozen` | Замораживается в течение 2 секунд, без отдельного уведомления (только badge/строка) |
| Приложение закрылось само | Строка становится `Not running`; из состояния заморозки удаляется |
| Quit | Подтверждение при заморозке; при выходе все возобновляются |
| Сон/пробуждение Mac | После wake — проверка сразу, без «мигания» статусов |
| Ошибка проверки IP | Статус `unknown`, по истечении grace — заморозка (по умолчанию), уведомление |
| Смена Wi-Fi на Ethernet с тем же VPN IP | Никакой заморозки, статус остаётся `protected` |

Тайминги:

- UI обновляется не позднее 200 мс после смены состояния.
- Countdown точен ±100 мс.
- Иконка в menu bar меняется вместе со статусом, без задержки.

---

## 9. Тексты

### Tone of voice

- Спокойный, короткий, без обвинений и драматизма.
- Sentence case, без восклицательных знаков.
- Скандинавский колорит — сдержанный и сухой, как хорошая сага: одна метафора на экран, не больше.
- Технические термины — простыми словами.
- В английском — neutral international English. В русском — без канцелярита.

### Ключевые строки (полный набор — в `copy.json`)

| Key | EN | RU |
|---|---|---|
| brand.name | No-halla | No-halla |
| brand.tagline | Valhalla can wait. | Вальхалла подождёт. |
| status.protected | Protected | Защищено |
| status.protected.lore | The gate is open. | Ворота открыты. |
| status.checking | Checking… | Проверяем… |
| status.checking.lore | Testing the gate. | Проверяем ворота. |
| status.grace | VPN lost — freezing in %ds | VPN пропал — заморозка через %d с |
| status.grace.lore | The gate is closing. | Ворота закрываются. |
| status.frozen | Frozen | Заморожено |
| status.frozen.lore | The gate is closed. | Ворота закрыты. |
| status.unknown | Can't verify IP | Не удаётся проверить IP |
| status.unknown.lore | The gate doesn't answer. | Ворота не отвечают. |
| status.paused | Protection off until %@ | Защита выключена до %@ |
| status.paused.lore | The gate is open. | Ворота открыты. |
| status.disabled | Protection off | Защита выключена |
| status.disabled.lore | The gate is open. | Ворота открыты. |
| status.setup | Set up trusted IP | Добавьте доверенный IP |
| status.setup.lore | No trusted realm yet. | У ворот пока нет доверенного мира. |
| status.bypass | Bypassing until %@ | Обход до %@ |
| status.bypass.lore | The gate is ajar. | Ворота приоткрыты. |
| network.currentIP | Current IP | Текущий IP |
| network.vpnInterface | VPN interface | VPN-интерфейс |
| network.trusted | Trusted | Доверенный |
| network.addCurrentIP | Add current IP | Добавить текущий IP |
| apps.title | Protected apps | Защищённые приложения |
| apps.add | Add app | Добавить приложение |
| apps.empty | No one is guarding the gate yet | Ворота пока никто не охраняет |
| apps.choose | Choose apps | Выбрать приложения |
| apps.active | Active | Активно |
| apps.frozen | Frozen | Заморожено |
| apps.notRunning | Not running | Не запущено |
| action.freezeNow | Freeze now | Заморозить сейчас |
| action.cancel | Cancel | Отмена |
| action.resumeAll | Resume all | Возобновить все |
| action.retry | Retry | Повторить |
| action.pause | Pause | Пауза |
| action.pause15 | 15 minutes | 15 минут |
| action.pause60 | 1 hour | 1 час |
| action.pauseUntilRelaunch | Until relaunch | До перезапуска |
| action.turnOn | Turn on now | Включить сейчас |
| action.quit | Quit | Выйти |
| action.settings | Settings | Настройки |
| caption.resumeBypass | Apps will unfreeze for 5 minutes, then protection resumes. | Приложения возобновятся на 5 минут, затем защита включится снова. |
| onboarding.1.title | Keep the gate closed when the VPN falls | Закрывайте ворота, когда падает VPN |
| onboarding.1.body | No-halla watches your IP. If it leaves the trusted realm, selected apps wait at the gate and blocked sites stop resolving until your VPN returns. | No-halla следит за IP. Если он покидает доверенный мир, выбранные приложения ждут у ворот, а заблокированные сайты перестают резолвиться, пока VPN не вернётся. |
| onboarding.2.title | Choose who waits at the gate | Выберите, кто будет ждать у ворот |
| onboarding.3.title | Trust your VPN's realm | Доверьтесь миру вашего VPN |
| onboarding.3.body | Only this IP opens the gate. Add your VPN IP here. | Только этот IP открывает ворота. Добавьте сюда IP вашего VPN. |
| onboarding.launchAtLogin | Launch No-halla at login | Запускать No-halla при входе |
| onboarding.skip | Skip setup | Пропустить настройку |
| notification.frozen.title | The gate is closed | Ворота закрыты |
| notification.frozen.body | Your IP changed to %@. %@ are waiting at the gate until your VPN returns. | Ваш IP изменился на %@. %@ ждут у ворот, пока VPN не вернётся. |
| notification.resumed.title | The gate is open | Ворота открыты |
| notification.resumed.body | Trusted IP is back. %@ are running again. | Доверенный IP вернулся. %@ снова работают. |
| notification.unknown.title | The gate doesn't answer | Ворота не отвечают |
| notification.unknown.body | No-halla can't reach the IP check services. Protected apps will stay frozen until the check succeeds. | No-halla не может связаться с сервисами проверки IP. Защищённые приложения останутся замороженными, пока проверка не пройдёт. |
| quit.title | Quit No-halla? | Выйти из No-halla? |
| quit.body | %d frozen apps will be resumed. The gate will open and protection will stop until you launch No-halla again. | %d замороженных приложений будут возобновлены. Ворота откроются, защита остановится до следующего запуска No-halla. |
| quit.confirm | Quit and Resume | Выйти и возобновить |
| empty.noTrusted | No trusted realm yet. Protection can't start. | У ворот пока нет доверенного мира. Защита не может начаться. |
| empty.offline | You're offline. The gate will be checked when the network is back. | Вы офлайн. Ворота будут проверены, когда сеть вернётся. |

Запрещено: «Oops», «Uh oh», «Something went wrong», эмодзи, CAPS LOCK, «Please» в каждой строке, слова «death», «kill», «warrior», «sacrifice» в UI.

---

## 10. Визуальный язык

### 10.1. Основа — dark-first нативная оболочка

- Тёмная тема — первичная цель дизайна и референс макетов; светлая — полноценная адаптация той же структуры. Приложение следует системной теме (не форсирует тёмную).
- Оболочка тонирована миром: тёмный фон — глубокий фьорд, группы и контролы — фьордовые тона, не нейтрально-серые. Цвет владеет всей поверхностью («committed shell»), а не один акцент на сером.
- Нативные материалы и контролы: `popover` material, `Form`/`List`, стандартные кнопки, toggle, поля, системные отступы. Никаких кастомных заголовков окон и «карточек в карточках».
- Плотность — как у системных menu bar приложений Apple: компактно, но не тесно.
- Бренд-слой (бронза, орнамент, фьорд) живёт в оболочке и идентичности, но не меняет системные контролы и не подменяет семантические цвета статусов.

### 10.2. Бренд-слой

Скандинавия живёт в оболочке и бренд-моментах:

1. **Оболочка (dark-first).** Фьордовый фон и группы; бронзовая «линия ворот» под шапкой; тонкий бронзовый ободок статус-пилюли; бронзовое подчёркивание выбранной вкладки настроек (лейбл остаётся акцентным синим); бронзовый «waiting»-ободок замороженной строки приложения. Бронза — идентичность и декор, не смысл статуса и не текст.
2. **Иконка приложения.** Круглый бронзовый щит с центральным умбоном и двумя вертикальными полосами паузы на фоне глубокого фьорда. По ободу — геометрический рунический орнамент (24 коротких штриха, не буквы). Без текста, без рогов, без топоров. 1024×1024, читается на 16 px. Предложи 2 концепта, выбери один.
3. **Menu bar glyph.** Монохромный template-щит 18×18 с паузами; 5 состояний. Без бронзы и орнамента — только глиф.
4. **Иллюстрации онбординга и пустых состояний.** Геометрический line art 1.5 px: ворота, щит, горизонт фьорда. Слоистая глубина (дальний хребет + ворота), тональный фьорд-градиент фона, бронза/кость. Симметрия, без лиц, оружия, черепов и «викингских» клише. Богаче прежнего минимализма, но всё ещё сдержанно.
5. **About.** Иконка, tagline, hero-иллюстрация ворот, орнамент-разделитель, ссылка на репозиторий.
6. **Орнамент.** 24 штриха (мотив иконки) как повторяющийся разделитель секций и линия ворот. Только SVG-графика, не Unicode-руны.

### 10.3. Палитра

Брендовая палитра питает и иконку/иллюстрации, и тёмную оболочку. Семантические цвета статусов — отдельные (10.5); бронза не подменяет их.

**Бренд:**

| Роль | Light | Dark | Где использовать |
|---|---|---|---|
| Fjord (глубокий фон) | #16323B | #0E1F26 | фон иконки, иллюстрации, тёмная оболочка |
| Fjord light (дымка) | #2A4A55 | #1C333D | второй план иллюстраций, тёмные группы/поверхности |
| Bronze (основной металл) | #B5763A | #D9A066 | щит, орнамент, линия ворот, ободки, акцент идентичности |
| Bronze highlight | #D9A066 | #E8BE8A | блики, обод |
| Bone (светлый штрих) | #E8E0D0 | #E8E0D0 | декоративные линии иллюстраций на тёмном (не текст) |
| Ember (только иллюстрации) | #C65A3A | #D9765A | редкий акцент иллюстраций, не для статусов |

**Оболочка UI (dark-first; светлая — адаптация):**

| Роль | Dark (первичный) | Light | Контраст |
|---|---|---|---|
| Фон оболочки (bg) | #0E1F26 | #F5F6FA | текст 15.5:1 |
| Группы/поверхности (surface) | #1C333D | #FFFFFF | текст 12.1:1 |
| Chrome (toolbar/footer) | #14252D | #EEF1F7 | — |
| Контролы (control) | #24404B | #F0F3F8 | — |
| Граница контрола (control-line) | #7E8DA3 | #7B889C | ≥3:1 к control |
| Разделитель (line) | #2E4A52 | #D9E0EB | декор; усилить в Increase Contrast |
| Текст primary | #F2F5FA | #182130 | ≥4.5:1 |
| Текст secondary (muted) | #A9B8C4 | #515F72 | 6.5:1 на surface |
| Бронза-акцент UI | #D9A066 | #B5763A | 7.4:1 на фоне (не текст) |

Правила бронзы в UI: шапка / линия ворот / ободок пилюли / подчёркивание вкладки (лейбл — акцентный синий) / waiting-ободок. Не для текста, не для смысла статуса, не вместо primary-кнопки. Primary — синий действия (10.5).

### 10.4. Токены интерфейса (обязательны в `tokens.json`)

| Категория | Значение |
|---|---|
| Spacing | 4 / 8 / 12 / 16 / 24 pt, сетка 4 |
| Corner radius | 6 (controls), 10 (cards), 14 (windows/sheets) |
| Popover width | 360 pt, padding 16 pt |
| Settings window | 680×520 pt |
| Onboarding window | 560×420 pt |
| App picker sheet | 480×520 pt |
| Row height (apps) | 44 pt |
| Status pill height | 22 pt, radius 11 |
| Icons in rows | 20×20 pt |
| Menu bar icon | 18×18 pt, template |
| Body font | SF Pro Text 13 pt |
| Lore subtitle | SF Pro Text 11 pt regular, secondary |
| Section title | SF Pro Text 11 pt semibold, uppercase, secondary |
| Title | SF Pro Display 17 pt semibold |
| Monospaced IP | SF Mono 13 pt |
| Hero title (онбординг/About) | SF Pro Display 22–24 pt semibold |
| Shell ground (dark / light) | #0E1F26 / #F5F6FA |
| Group surface (dark / light) | #1C333D / #FFFFFF |
| Chrome (dark / light) | #14252D / #EEF1F7 |
| Control (dark / light) | #24404B / #F0F3F8 |
| Control-line (dark / light) | #7E8DA3 / #7B889C |
| Separator (dark / light) | #2E4A52 / #D9E0EB |
| Bronze UI accent (dark / light) | #D9A066 / #B5763A |
| Gate-line | 1 pt, бронза, орнамент 24 штриха |

Тёмные значения — первичные, светлые — адаптация. Все пары обязаны проходить контраст (раздел 11). Новые токены оболочки должны появиться в `tokens.json` (формат light/dark/contrast).

### 10.5. Семантические цвета

В тёмной теме semantic-цвета — светлые тональные варианты (не «сырые» системные и не инверсия): они обязаны проходить 4.5:1 на фьордовой поверхности.

| Роль | Light | Dark | Использование |
|---|---|---|---|
| Success / Protected | #196542 | #88DDB1 | статус protected, «доверенный» |
| Warning / Grace | #854600 | #FFC784 | grace, bypass, unknown |
| Danger / Frozen | #A42338 | #FFA1AF | frozen, destructive reset |
| Primary / Action | #1B5EC4 | #2865C6 | primary buttons (белый текст ≥4.5:1) |
| Link / Accent | #1557AD | #94BCFF | ссылки, plain-действия, фокус, выбор вкладки |
| Text primary | #182130 | #F2F5FA | заголовки, строки |
| Text secondary | #515F72 | #A9B8C4 | подписи, helper text |
| Separator | #D9E0EB | #2E4A52 | границы секций |

Правила:

- Цвет никогда не единственный носитель смысла: всегда иконка/текст + цвет.
- Красный — только для реальной опасности/разрушительных действий. «Resume all» — primary/action, не красный.
- Бронза — идентичность и декор оболочки; не для смысла статуса, не для текста, не вместо primary.
- Градиенты: допустим мягкий тональный фьорд-градиент на оболочке и hero-иллюстрациях (dark-first) и градиент металла в иконке. На контролах, статусах и тексте — никаких градиентов. Без неона, свечения, glassmorphism.

### 10.6. Типографика и руны

- Только SF Pro / SF Mono. Никаких «скандинавских» шрифтов и рунических гарнитур.
- Иерархия: title 17 pt semibold (поповер/настройки); hero-заголовки онбординга и About — SF Pro Display 22–24 pt semibold; body 13 pt; label/caption 11 pt; IP — SF Mono 13 pt tabular.
- Рунический орнамент — только SVG-графика (24 штриха, мотив иконки). Не использовать Unicode-руны в тексте: шрифтовая поддержка непредсказуема.
- Заголовки онбординга могут иметь чуть больший tracking (+0.2), но не превращаться в логотип.

### 10.7. Motion

- Системные анимации переходов; спокойно, без вспышек и пульсаций.
- Countdown — линейный прогресс (бронзовый fill допустим), тик раз в секунду; без пульсаций.
- Линия ворот и ободок статуса могут мягко менять тон при смене состояния (одна короткая системная анимация), без свечения и «загорания рун».
- Смена иконки menu bar — без bounce.
- Reduce Motion: убрать все необязательные анимации; countdown снапится по тику.

---

## 11. Доступность

- VoiceOver label для иконки menu bar: «No-halla, protected», «No-halla, apps frozen», «No-halla, checking IP», «No-halla, protection off», «No-halla, can't verify IP».
- Все статусы доступны текстом, не только цветом/иконкой.
- Lore-подписи не заменяют функциональный статус; VoiceOver читает сначала статус, затем подпись.
- Полная навигация с клавиатуры: Tab/Shift-Tab, Space для toggle, Escape закрывает поповер/шит.
- Минимальная зона нажатия 28×28 pt.
- Контраст текста ≥ 4.5:1 в обеих темах (тёмная — первичная проверка); проверить Increase Contrast. Бронза на фьорде ≥ 3:1 для значимых нетекстовых элементов (ободок, линия ворот, индикаторы); для текста бронзу не использовать. Границы контролов ≥ 3:1 к поверхности контрола.
- Reduce Transparency: заменить materials на непрозрачные фьордовые поверхности.
- Уведомления дублируют состояние, но не являются единственным способом узнать о заморозке.
- Локализация: макеты должны выдерживать +30% длины строк (RU/DE).

---

## 12. Deliverables

Создай ровно эту структуру:

```
design/
├── DESIGN_SPEC.md          # IA, flows, screens, states, interactions, accessibility
├── BRAND.md                # название, tagline, метафора, словарь, палитра, иконки, do/don't
├── tokens.json             # цвета (UI + brand), типографика, spacing, размеры
├── copy.json               # все строки EN + RU, ключи как в разделе 9
├── COMPONENTS.md           # матрица компонентов: variants, sizes, states, do/don't
├── ICONS.md                # menu bar 5 состояний (SVG), app icon, SF Symbols mapping
├── ACCESSIBILITY.md        # чеклист и VoiceOver-подписи
├── HANDOFF.md              # маппинг экран → SwiftUI view → FR-ID → asset/string keys
├── OPEN_QUESTIONS.md       # только если есть реальные вопросы, с рекомендацией
├── mockups/
│   ├── popover-protected.html
│   ├── popover-grace.html
│   ├── popover-frozen.html
│   ├── popover-unknown.html
│   ├── popover-paused.html
│   ├── popover-empty.html
│   ├── onboarding-1.html
│   ├── onboarding-2.html
│   ├── onboarding-3.html
│   ├── settings-general.html
│   ├── settings-protection.html
│   ├── settings-advanced.html
│   ├── settings-about.html
│   ├── app-picker.html
│   └── quit-confirm.html
└── exports/
    ├── appicon-1024.png     # bronze gateway, 1024×1024
    ├── menubar-icons.svg    # 5 состояний, template
    └── brand-sheet.svg      # палитра, иконка, орнамент, tagline, тёмная оболочка + линия ворот
```

Требования к HTML-макетам:

- Self-contained: без CDN, внешних шрифтов и сетевых запросов.
- Шрифтовой стек: `-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif`.
- Каждый макет — отдельный файл; рядом с «экраном» можно показать подписи/размеры, но сам экран должен быть пиксельно аккуратным.
- Тёмная и светлая темы: через `prefers-color-scheme` и переключатель `data-theme="light|dark"`. Тёмная — первичный референс: каждый макет по умолчанию открывается в тёмной и проверен в ней; светлая — полноценная адаптация. Оболочка фьордовая (не серая), с бронзовой линией ворот и ободком пилюли.
- Масштаб 2x: canvas в CSS-пикселях, скриншоты/ревью — @2x.
- Никаких «рыбных» текстов: только реальные строки из `copy.json`.
- Состояния, которых нет в списке, но которые нужны для полноты (hover, focus, disabled) — показать в `COMPONENTS.md`, не плодить отдельные макеты.
- Брендовые иллюстрации — inline SVG, не растровые картинки.

Требования к `BRAND.md`:

1. Название, произношение, написание, tagline EN/RU.
2. Метафора и словарь (раздел 1.3), что можно и нельзя говорить.
3. Палитра с HEX и правилами применения.
4. Иконка приложения: 2 концепта, финальный, правила масштабирования (16/32/128/512/1024).
5. Menu bar glyph: 5 состояний, толщина штриха, поведение в light/dark.
6. Иллюстрации: стиль, толщина линии, симметрия, запрещённые клише.
7. Do / Don't с примерами.

Требования к `DESIGN_SPEC.md`:

1. Краткое описание продукта и принципов.
2. IA и карта переходов.
3. Таблица состояний (раздел 6) с маппингом на экраны.
4. Описание каждого экрана: layout, элементы, поведение, размеры.
5. Все edge cases из раздела 7.8.
6. Interaction-таблица из раздела 8.
7. Ссылки на макеты и токены.
8. Accessibility-раздел.
9. Список отклонений от брифа (если были) с обоснованием.

Требования к `HANDOFF.md`:

- Таблица: экран → имя SwiftUI view (например, `PopoverView`, `SettingsProtectionView`, `OnboardingTrustedRealmView`) → FR-ID из `IMPLEMENTATION_BRIEF.md` → используемые токены → ключи строк.
- Список ассетов: `AppIcon.appiconset`, `MenuBarIcon.imageset` (5 вариантов), брендовые SVG.
- Таблица технических идентификаторов: display name `No-halla`, target/module `NoHalla`, bundle ID `dev.nohalla.NoHalla`, support dir `NoHalla`.
- Явно указать, что источник правды: пиксели/тексты — дизайн, поведение — имплементационный бриф.

---

## 13. Запреты

- Не рисовать веб-приложение: кастомные рамки окон, sidebar, «карточки в карточках», декоративные тени вне системной elevation. Hero-заголовки онбординга/About и тональный фьорд-градиент оболочки допустимы (раздел 10).
- Не добавлять экраны, фичи и настройки, которых нет в этом документе.
- Не использовать эмодзи в UI.
- Не делать онбординг длиннее 3 шагов.
- Не прятать «Resume all» и «Quit».
- Не использовать красный как primary для безопасных действий.
- Не показывать вымышленные IP/имена приложений, противоречащие состояниям.
- Тёмная тема проектируется первой (dark-first), светлая — адаптация; не делать ни одну простым инвертированием другой. Оболочка — фьордовые тона, не нейтрально-серые.
- Не добавлять графики, историю, статистику, аккаунты, «AI»-визуал.
- Не добавлять звуки.
- **Не превращать UI в скандинавский китч:** никаких рогов, топоров, черепов, бородатых викингов, «VIKING»-леттеринга, рун вместо букв, пергамента, дерева и металлических текстур в контролах.
- Не использовать бронзу для текста, смысла статуса и primary-кнопки; бронза — идентичность и декор оболочки (раздел 10.3).
- Без неона, свечения, glassmorphism и градиентов на контролах, статусах и тексте.
- Не заменять функциональные подписи метафорами: пользователь должен понимать `Frozen` и `Resume all` без знания лора.

---

## 14. Критерии приёмки дизайна

Дизайн готов, когда:

- [ ] Есть все 15 HTML-макетов из раздела 12 и они открываются офлайн.
- [ ] Показаны все 8 состояний из раздела 6 (в поповере или в матрице состояний).
- [ ] Menu bar иконка имеет 5 различимых состояний + VoiceOver labels.
- [ ] Онбординг ровно 3 шага, с валидацией IP и toggle автозапуска.
- [ ] В настройках 4 вкладки, все поля из раздела 7.4, валидация и helper text.
- [ ] Все тексты есть в EN и RU, без «рыбы», тон соответствует разделу 9.
- [ ] Тёмная тема — первичный референс: каждый макет открывается в тёмной, оболочка фьордовая (не серая), проверена в тёмной.
- [ ] Бронза присутствует как акцент оболочки (линия ворот, ободок пилюли) и не используется для текста / смысла статуса / primary.
- [ ] Светлая тема — полноценная адаптация, проверена отдельно.
- [ ] Контраст проверен в тёмной: текст ≥4.5:1, бронза и границы контролов ≥3:1.
- [ ] Контраст и клавиатурная навигация проверены по чеклисту.
- [ ] `tokens.json` валиден и используется во всех макетах.
- [ ] `HANDOFF.md` маппит каждый экран на view и FR-ID.
- [ ] Нет фич вне scope; все вопросы — в `OPEN_QUESTIONS.md` с рекомендацией.
- [ ] `BRAND.md` содержит tagline, словарь, палитру, 2 концепта иконки и do/don't.
- [ ] Иконка приложения читается на 16 px; menu bar glyph — на 18 px.
- [ ] В дизайне нет скандинавского китча и рун вместо текста.
- [ ] Функциональные статусы и кнопки остались понятными без метафор.

---

## 15. Инструменты и порядок работы

1. Прочитай этот бриф и `IMPLEMENTATION_BRIEF.md` (раздел с FR-ID нужен для `HANDOFF.md`).
2. Сначала создай `BRAND.md`, `DESIGN_SPEC.md` и `tokens.json`.
3. Затем иконку приложения и menu bar glyph — утверди визуальный язык.
4. После этого макеты: начни с `popover-protected` в тёмной теме (dark-first), затем остальные состояния и экраны; светлую проверь как адаптацию.
5. После макетов — `copy.json`, `COMPONENTS.md`, `ICONS.md`, `ACCESSIBILITY.md`, `HANDOFF.md`.
6. Проверь себя по чеклисту раздела 14.
7. Если доступны скиллы `ui-ux-pro-max`, `design`, `high-end-visual-design`, `imagegen` — используй их для качества, но не меняй scope и не добавляй «вау-эффекты» в ущерб нативности macOS.

Работай автономно. Не задавай вопросов, если ответ можно вывести из брифа; спорные места фиксируй в `OPEN_QUESTIONS.md` с рекомендацией по умолчанию.