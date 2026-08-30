# Gamma Arena: текущий баланс генерации

Этот документ — рабочая панель балансировки режима Arena. Он отвечает на три
вопроса: что получает игрок, что получает команда противников и какими правилами
эти значения превращаются в конкретный бой.

Числовые таблицы ниже генерируются непосредственно из production-конфигов и
именованных констант production-скриптов. Чтобы обновить их после изменения
баланса:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Update-GammaArenaBalanceDoc.ps1
```

Проверить актуальность документа без записи:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Update-GammaArenaBalanceDoc.ps1 -Verify
```

Обозначения диагностик:

- `fact` — значение или правило непосредственно задано production-источником;
- `derived` — результат детерминированного расчёта над текущими значениями;
- `blind_spot` — вывод требует установленного merge или игрового измерения.

> Важно: `actor_budget` — бюджет одного комплекта игрока, а `enemy_budget` —
> общий бюджет всей команды вместе со стоимостью профилей NPC. Сравнивать эти
> числа как прямое отношение силы нельзя.

## Паспорт источников

<!-- BEGIN GENERATED: state-passport -->
| Source | Version |
|---|---|
| Catalog | schema 10 / revision 11 / generator 11 |
| Difficulties | schema 4 / revision 5 |
| Layout | schema 2 / revision 2 |
| Tactics | schema 1 / revision 1 |
<!-- END GENERATED: state-passport -->

## Custom Arena setup

Custom mode keeps one enemy faction for the full cohort, exposes one exact-rank
selector per opponent, and uses Arena equipment points for the installed combat
inventory. The following contract is generated from the active custom rules,
item catalog, layout, FightSpec schema, and catalog identity.

<!-- BEGIN GENERATED: custom-setup -->
| custom policy | value |
|---|---|
| FightSpec/catalog identity | 9/10/11/11 |
| enemy faction | one shared faction for the complete cohort |
| opponent selectors | 1-10 ordered exact-rank selectors; Rostok capacity 10 |
| exact ranks | novice, trainee, experienced, professional, veteran, expert, master, legend |
| player budget formula | base_budget + sum(rank threat) |
| base_budget | 600 Arena points |
| distinct physical section cap | 64 across inventory and optional device |
| physical item cap | 256 entities per participant |
| selectable installed categories | weapon, ammo, outfit, helmet, knife, medicine, grenade |
| Arena-controlled enemy rerolls | numeric rank, equipment, ammunition, medicine, grenade, spawn, tactical route |
| integrity retry | reuses the same validated FightSpec v9 |
| appearance boundary | X-Ray `specific_character` is not seeded or stored in FightSpec v9 |
| deterministic appearance follow-up | cataloged aliases, fingerprint/validator membership, and catalog identity advance |
| maximum selected grenades | 2 distinct sections |
| quantity per selected grenade | exactly 1 |
| first selected grenade | base Arena-point price |
| second selected grenade | 2x its own base Arena-point price |

| exact rank | threat | one-opponent budget |
|---|---:|---:|
| novice | 100 | 700 |
| trainee | 120 | 720 |
| experienced | 150 | 750 |
| professional | 180 | 780 |
| veteran | 220 | 820 |
| expert | 270 | 870 |
| master | 330 | 930 |
| legend | 600 | 1200 |

| budget example | roster | Arena points |
|---|---|---:|
| one novice | novice | 700 |
| one legend | legend | 1200 |
| ten novices | novice x10 | 1600 |
| ten legends | legend x10 | 6600 |
<!-- END GENERATED: custom-setup -->

## Карта генерации боя

```mermaid
flowchart TD
    request["seed + difficulty + fight_index"] --> envelope["Параметры сложности"]

    envelope --> actorPair["Игрок: доступные пары классов"]
    actorPair --> actorWeighted["Вес пары = вес оружия × вес брони"]
    actorWeighted --> actorItems["Конкретные предметы внутри класса"]
    actorItems --> actorLoadout["Оружие + патроны + броня + нож"]
    envelope --> actorMedical["Отдельный медицинский бюджет и веса категорий"]
    actorMedical --> actorLoadout

    envelope --> enemyCount["Число противников"]
    enemyCount --> slotBudget["Общий бюджет → бюджеты слотов"]
    slotBudget --> faction["Одна фракция на бой"]
    faction --> profiles["Профили NPC по рангу"]
    profiles --> roles["leader / primary / secondary"]
    roles --> enemyItems["Фракционный пул оружия или глобальный fallback"]
    enemyItems --> enemyLoadouts["Профиль + экипировка в бюджете слота"]
    enemyCount --> enemyMedical["Командный пул бинтов и аптечек"]

    enemyCount --> spawn["Нативные и виртуальные точки появления"]
    spawn --> routes["Стартовые тактические маршруты"]

    actorLoadout --> spec["FightSpec v9"]
    enemyLoadouts --> spec
    enemyMedical --> spec
    routes --> spec
```

Случайность детерминирована входным seed, индексом боя и версиями каталога и
раскладки. Одинаковые входы дают одинаковый `FightSpec`.

## Сводка сложностей

<!-- BEGIN GENERATED: difficulty-dashboard -->
| difficulty | enemy_count | enemy_budget | actor_gear_budget | actor_medical_budget | primary_share |
|---|---:|---:|---:|---:|---:|
| rookie | 2-3 | 25 | 7 | 4 | 50% |
| stalker | 3-5 | 50 | 10 | 5 | 60% |
| veteran | 5-7 | 75 | 13 | 6 | 75% |
| master | 7-10 | 100 | 15 | 8 | 80% |

| weapon_class | rookie | stalker | veteran | master |
|---|---|---|---|---|
| w_pistol | 50% #####..... | 25% ###....... | 10% #......... | 5% #......... |
| w_smg | 30% ###....... | 35% ####...... | 25% ###....... | 15% ##........ |
| w_shotgun | 15% ##........ | 20% ##........ | 20% ##........ | 15% ##........ |
| w_rifle | 5% #......... | 18% ##........ | 38% ####...... | 50% #####..... |
| w_sniper | 0% .......... | 2% .......... | 7% #......... | 15% ##........ |

| armor_class | rookie | stalker | veteran | master |
|---|---|---|---|---|
| light | 55% ######.... | 30% ###....... | 15% ##........ | 10% #......... |
| medium | 30% ###....... | 40% ####...... | 30% ###....... | 25% ###....... |
| scientific | 10% #......... | 20% ##........ | 25% ###....... | 25% ###....... |
| heavy | 5% #......... | 9% #......... | 25% ###....... | 35% ####...... |
| powered_exo | 0% .......... | 1% .......... | 5% #......... | 5% #......... |
<!-- END GENERATED: difficulty-dashboard -->

## Медицинские комплекты

Медицина игрока генерируется независимо от оружия и брони. В комплект всегда
входят бинт и один предмет категорий `health`/`rare`, после чего до трёх
дополнительных предметов выбираются по весам сложности, доступному остатку,
минимальному tier и ограничениям количества. Поэтому расширение медицинского
пула не отнимает бюджет у основной экипировки.

<!-- BEGIN GENERATED: medical-loadouts -->
| difficulty | tier | medical_budget | bleed | health | boost | rare |
|---|---:|---:|---:|---:|---:|---:|
| rookie | 1 | 4 | 35% | 50% | 15% | 0% |
| stalker | 2 | 5 | 25% | 50% | 25% | 0% |
| veteran | 3 | 6 | 20% | 45% | 30% | 5% |
| master | 4 | 8 | 15% | 40% | 35% | 10% |

| difficulty | budget policy | mandatory items | optional slots | item cap |
|---|---|---|---:|---:|
| rookie | independent 4 points | bandage + health/rare healer | 3 | 5 |
| stalker | independent 5 points | bandage + health/rare healer | 3 | 5 |
| veteran | independent 6 points | bandage + health/rare healer | 3 | 5 |
| master | independent 8 points | bandage + health/rare healer | 3 | 5 |

| section | category | actor_cost | npc_cost | min_tier | max_count |
|---|---|---:|---:|---:|---:|
| bandage | bleed | 1 | 1 | 1 | 2 |
| jgut | bleed | 2 | 0 | 1 | 1 |
| stimpack | health | 2 | 0 | 1 | 1 |
| medkit | health | 3 | 2 | 1 | 1 |
| analgetic | boost | 2 | 0 | 1 | 1 |
| drug_booster | boost | 2 | 0 | 1 | 1 |
| stimpack_army | health | 3 | 0 | 2 | 1 |
| salicidic_acid | boost | 3 | 0 | 2 | 1 |
| cocaine | boost | 3 | 0 | 2 | 1 |
| medkit_army | health | 4 | 0 | 3 | 1 |
| stimpack_scientic | health | 4 | 0 | 3 | 1 |
| morphine | boost | 4 | 0 | 3 | 1 |
| medkit_scientic | health | 5 | 0 | 4 | 1 |
| adrenalin | boost | 5 | 0 | 4 | 1 |
| survival_kit | rare | 6 | 0 | 4 | 1 |
| rebirth | rare | 7 | 0 | 4 | 1 |
<!-- END GENERATED: medical-loadouts -->

## Гранаты в комплектах

Гранаты генерируются независимо от экипировки и медицины. Это физические
предметы инвентаря с нулевой стоимостью; решение о броске у NPC остаётся за
нативным AI и требует фактического наличия гранаты.

<!-- BEGIN GENERATED: grenade-loadouts -->
| participant | count | probability |
|---|---|---:|
| actor | none | 94% |
| actor | exactly 1 | 5% |
| actor | exactly 2 | 1% |
| each opponent | none | 90% |
| each opponent | exactly 1 | 10% |

| policy | value |
|---|---|
| actor_pool | grenade_f1, grenade_rgd5, grenade_gd-05 |
| opponent_pool | grenade_f1, grenade_rgd5, grenade_gd-05 |
| two_actor_picks | independent; duplicates allowed |
| budget_cost | 0; outside gear and medical budgets |
| NPC use | physical possession required; native AI decides whether to throw |
<!-- END GENERATED: grenade-loadouts -->

## Actor lighting device

Random always equips exactly one outside-budget device. Custom uses an optional dedicated selector whose default is No device; a selected device spends its fixed AP price.

<!-- BEGIN GENERATED: actor-devices -->
| device | section | kind | NV effect | Random probability | Custom price |
|---|---|---|---|---:|---:|
| headlamp | device_torch_dummy | headlamp | none | 50% | 25 AP |
| nv_gen1 | device_torch_nv_1 | gen1 | nightvision_1 | 25% | 75 AP |
| nv_gen2 | device_torch_nv_2 | gen2 | nightvision_2 | 18% | 150 AP |
| nv_gen3 | device_torch_nv_3 | gen3 | nightvision_3 | 7% | 300 AP |

| policy | value |
|---|---|
| recipient | actor only; opponents never receive a device |
| Random | exactly one automatically selected device; mandatory and outside every loadout budget |
| Custom | optional dedicated selector; No device is the default and a selection spends its fixed AP price |
| difficulty | independent of difficulty |
| equip state | slot 10; full charge |
| activation | manual; never enabled automatically |
| universal FightSpec | one mode-neutral v9 item shape; no mode, budget, price, weight total, or generation provenance |
<!-- END GENERATED: actor-devices -->

## Использование медицины противниками

Противникам выдаются только физически поддержанные контроллером `bandage` и
`medkit`. Командный медицинский бюджет равен числу противников; получатели
выбираются с весами ролей leader/primary/secondary = 4/2/1. Аптечка имеет
приоритет при низком здоровье, бинт — при кровотечении. Предмет списывается из
реального инвентаря один раз, а лечение отменяется при смерти, критическом
состоянии, завершении боя, потере или передаче предмета.

<!-- BEGIN GENERATED: npc-medical-runtime -->
| runtime policy | value |
|---|---|
| reconciliation_period | 250 ms |
| core_rng_epoch | 6 |
| loadout_medical_rng_epoch | 1 |
| npc_action_rng_epoch | 1 |
| health_trigger | < 0.60 |
| bleed_trigger | > 0.15 |
| medkit_pulses | 13 |
| medkit_health_per_pulse | +0.05 |
| medkit_bleeding_cap | 0.01 |
| bandage_bleeding_cap | 0.07 |
| actor_item_cap | 5 |
| enemy_team_medical_budget | opponent_count points |

| NPC rank | deterministic action delay |
|---|---:|
| novice | 2000-2500 ms |
| trainee | 1500-2000 ms |
| experienced | 1000-1500 ms |
| veteran | 500-1000 ms |
<!-- END GENERATED: npc-medical-runtime -->

Проценты в матрицах — веса классов, а не обещанная частота конкретного предмета.
Если пара классов не имеет ни одного полного комплекта в бюджете, она исключается
до броска, а оставшиеся веса фактически перенормируются.

## Экипировка игрока

Порядок выбора принципиален:

1. Генератор проверяет, какие пары `weapon class × armor class` имеют хотя бы
   один полный комплект в `player_gear_budget`.
2. Вес доступной пары равен произведению двух настроек сложности.
3. После выбора пары конкретное оружие выбирается равновероятно среди доступных
   секций этого класса.
4. Затем выбирается допустимое бюджетное число коробок обычных патронов.
5. Конкретный костюм выбирается равновероятно среди доступных секций выбранного
   класса.
6. В комплект входит случайный нож из каталога; медицинский набор генерируется
   отдельно по правилам предыдущего раздела.

Таким образом, число предметов внутри класса не меняет вероятность самого
класса, но меняет вероятность отдельной секции после выбора класса.

После завершения бюджетного выбора генератор вычисляет конечное число коробок
обычных патронов. К базовому запасу не менее трёх магазинов добавляется одна
гарантированная коробка и независимый шанс ещё одной коробки за каждого
противника. Эта добавка не входит в `player_gear_budget`, не имеет балансового
потолка и записывается прямо в конечное поле FightSpec `ammo_boxes`; runtime
создаёт ровно указанное там количество патронов. Правила боезапаса и лута
противников при этом не меняются.

<!-- BEGIN GENERATED: actor-equipment -->
`gear_cost = weapon + ammo_cost * budgeted_boxes + outfit`; scaled ordinary boxes and medicine are outside this budget
`scaled_boxes = 1 + independent success per opponent`; deterministic stream `actor_scaled_ammo:<index>`, range `1..N+1`, no balance ceiling
`final ammo_boxes = max(budgeted_boxes, ceil(3 * magazine_size / box_size)) + scaled_boxes`; FightSpec stores only this final value

| player weapon kind | per-opponent chance | guaranteed scaled boxes | scaled range | E[N=1] | E[N=5] | E[N=20] | E[N=100] |
|---|---:|---:|---|---:|---:|---:|---:|
| w_pistol | 40% | 1 | 1..N+1 | 1.4 | 3 | 9 | 41 |
| w_smg | 25% | 1 | 1..N+1 | 1.25 | 2.25 | 6 | 26 |
| w_shotgun | 25% | 1 | 1..N+1 | 1.25 | 2.25 | 6 | 26 |
| w_rifle | 20% | 1 | 1..N+1 | 1.2 | 2 | 5 | 21 |
| w_sniper | 10% | 1 | 1..N+1 | 1.1 | 1.5 | 3 | 11 |

| installed weapon kind | Arena cost |
|---|---:|
| w_pistol | 2 |
| w_smg | 4 |
| w_shotgun | 5 |
| w_rifle | 5 |
| w_sniper | 6 |

| installed outfit kind | Arena cost | emitted armor class |
|---|---:|---|
| o_light | 1 | light |
| o_medium | 3 | medium |
| o_sci | 4 | scientific |
| o_heavy | 5 | heavy; powered_exo when exo/proto |

| difficulty | affordable fallback pairs | unavailable fallback pairs |
|---|---:|---:|
| rookie | 4 / 25 | 21 / 25 |
| stalker | 10 / 25 | 15 / 25 |
| veteran | 12 / 25 | 13 / 25 |
| master | 12 / 25 | 13 / 25 |

| difficulty | weapon_class | affordable armor classes | unavailable armor classes |
|---|---|---|---|
| rookie | w_pistol | light, medium, scientific | heavy, powered_exo |
| rookie | w_smg | light | medium, scientific, heavy, powered_exo |
| rookie | w_shotgun | - | light, medium, scientific, heavy, powered_exo |
| rookie | w_rifle | - | light, medium, scientific, heavy, powered_exo |
| rookie | w_sniper | - | light, medium, scientific, heavy, powered_exo |
| stalker | w_pistol | light, medium, scientific | heavy, powered_exo |
| stalker | w_smg | light, medium, scientific | heavy, powered_exo |
| stalker | w_shotgun | light, medium | scientific, heavy, powered_exo |
| stalker | w_rifle | light, medium | scientific, heavy, powered_exo |
| stalker | w_sniper | - | light, medium, scientific, heavy, powered_exo |
| veteran | w_pistol | light, medium, scientific | heavy, powered_exo |
| veteran | w_smg | light, medium, scientific | heavy, powered_exo |
| veteran | w_shotgun | light, medium, scientific | heavy, powered_exo |
| veteran | w_rifle | light, medium, scientific | heavy, powered_exo |
| veteran | w_sniper | - | light, medium, scientific, heavy, powered_exo |
| master | w_pistol | light, medium, scientific | heavy, powered_exo |
| master | w_smg | light, medium, scientific | heavy, powered_exo |
| master | w_shotgun | light, medium, scientific | heavy, powered_exo |
| master | w_rifle | light, medium, scientific | heavy, powered_exo |
| master | w_sniper | - | light, medium, scientific, heavy, powered_exo |

| fallback weapon | kind | cost | ammo | boxes |
|---|---|---:|---|---:|
| wpn_pm | w_pistol | 2 | ammo_9x18_fmj | 1-2 |
| wpn_mp5 | w_smg | 4 | ammo_9x19_fmj | 1-2 |
| wpn_ak74u | w_rifle | 5 | ammo_5.45x39_fmj | 1-2 |
| wpn_ak74 | w_rifle | 6 | ammo_5.45x39_fmj | 1-2 |
| wpn_wincheaster1300 | w_shotgun | 5 | ammo_12x70_buck | 1-2 |

| fallback outfit | armor_class | cost |
|---|---|---:|
| novice_outfit | light | 1 |
| stalker_outfit | medium | 3 |
| banditmerc_outfit | scientific | 4 |

| ammunition | Arena cost | source mode |
|---|---:|---|
| ammo_9x18_fmj | 1 | fallback |
| ammo_9x19_fmj | 1 | fallback |
| ammo_5.45x39_fmj | 2 | fallback |
| ammo_12x70_buck | 2 | fallback |
| dynamic discovered ammo | 1 | runtime discovery |

| extra item | Arena cost | selection |
|---|---:|---|
| bandage | 1 | medical pool: mandatory actor baseline; NPC-capable |
| medkit | 2 | medical pool: NPC-capable |
| knives | 9 | no budget cost; uniform section pick |
| knife sections | - | wpn_knife, wpn_knife2, wpn_knife3, wpn_knife4, wpn_knife5, wpn_knife6, wpn_knife7, wpn_knife8, wpn_knife9 |
<!-- END GENERATED: actor-equipment -->

### Динамический каталог GAMMA

Fallback-списки выше гарантированы самим репозиторием, но не являются полным
runtime-каталогом. При запуске Arena читает effective system merge GAMMA и
добавляет семантически подходящие предметы:

- оружие должно иметь поддерживаемый `kind`, слот и валидный магазин/боеприпас;
- броня должна иметь поддерживаемый `kind` и занимать слот костюма;
- экзоскелет определяется отдельно как `powered_exo` по данным Powered Exos;
- нож должен быть melee-секцией семейства `wpn_knife`;
- стоимость назначается классу Arena, а не рыночной цене конкретного предмета.

После экипировки силовой экзоскелет инициализируется и проверяется на полный
заряд. Отдельный аккумулятор или PSU в бюджет не входит.

## Противники и их экипировка

Общий бюджет противников делится на число участников через частное и остаток.
Первые слоты получают по одному дополнительному очку, пока остаток не исчерпан.
Поэтому таблица показывает каждый реально возможный набор бюджетов, а не только
среднее значение.

Первый слот всегда `leader` и использует primary-пул. Число primary-слотов
округляется вверх; оставшиеся слоты используют secondary-пул. В dynamic-режиме
одна фракция выбирается на весь бой, после чего генератор старается использовать
её effective GAMMA weapon pools. Пустой или недоступный ролевой пул заменяется
глобальным пулом той же роли.

Профиль NPC и комплект выбираются не обязательно с максимальной стоимостью.
Граница верхней ценовой полосы вычисляется точно как
`threshold = ceil(maximum * 70 / 100)`. Для профиля `maximum` — наибольшая
стоимость среди доступных профилей. Для комплекта `maximum` — оставшийся после
профиля бюджет экипировки. Выбор внутри полосы равновероятный; если полоса пуста,
генератор оставляет только самые дорогие из доступных вариантов
(`highest-affordable fallback`). После появления снайперского оружия оно исключается из
пулов следующих слотов.

<!-- BEGIN GENERATED: opponent-budgets -->
| difficulty | opponents | slot budgets | primary incl. leader | secondary |
|---|---:|---|---:|---:|
| rookie | 2 | 13, 12 | 1 | 1 |
| rookie | 3 | 9, 8, 8 | 2 | 1 |
| stalker | 3 | 17, 17, 16 | 2 | 1 |
| stalker | 4 | 13, 13, 12, 12 | 3 | 1 |
| stalker | 5 | 10 x 5 | 3 | 2 |
| veteran | 5 | 15 x 5 | 4 | 1 |
| veteran | 6 | 13, 13, 13, 12, 12, 12 | 5 | 1 |
| veteran | 7 | 11, 11, 11, 11, 11, 10, 10 | 6 | 1 |
| master | 7 | 15, 15, 14, 14, 14, 14, 14 | 6 | 1 |
| master | 8 | 13, 13, 13, 13, 12, 12, 12, 12 | 7 | 1 |
| master | 9 | 12, 11, 11, 11, 11, 11, 11, 11, 11 | 8 | 1 |
| master | 10 | 10 x 10 | 8 | 2 |

| profile rank | profile cost |
|---|---:|
| novice | 1 |
| trainee | 2 |
| experienced | 3 |
| veteran | 4 |

| rule | value |
|---|---:|
| PRIMARY_BAND_PERCENT | 70% |
| selection_band_threshold | ceil(maximum * 70 / 100) |
| max_snipers_per_fight | 1 |
| faction_per_fight | 1 |
| supported_factions | army, bandit, csky, dolg, ecolog, freedom, killer, monolith, stalker |
| appearance_reproducibility | deferred; X-Ray `specific_character` is not seeded or stored in FightSpec v9 |
| appearance_gameplay_effect | none; faction, rank, equipment, budget, and combat rules remain authoritative |
| deterministic_appearance_follow_up | cataloged appearance aliases + fingerprint/validator membership + catalog identity advance |
| opponent_total_cost | profile + gear + assigned medicine |
<!-- END GENERATED: opponent-budgets -->

Нож не расходует бюджет. Итоговая стоимость противника складывается из профиля,
экипировки и назначенной ему доли отдельного командного медицинского пула.

## Геометрия арены и тактический директор

Параметры раскладки ограничивают допустимое число противников и безопасность
виртуальных точек. Тактический директор не добавляет очки экипировки: он меняет
только маршруты, распределение ролей и обмен сведениями о позиции игрока.

<!-- BEGIN GENERATED: arena-tactics -->
| layout parameter | value |
|---|---:|
| actor_spawn_path | t_way |
| actor_look_path | t_look |
| native_opponent_paths | 6 |
| virtual_capacity | 10 |
| virtual_radii | 1.5, 2.5 m |
| max_height_delta | 1 m |
| min_opponent_separation | 1.75 m |
| min_actor_separation | 8 m |
| max_base_distance | 3 m |

| tactical parameter | value |
|---|---|
| observation_interval_ms | 500 ms |
| report_delay_ms | 1000-3000 ms |
| assignment_dwell_ms | 5000 ms |
| visual_aging_ms | 20000 ms |
| evidence_expiry_ms | 60000 ms |
| hint_delay_ms | 60000 ms |
| hint_cooldown_ms | 60000 ms |
| initial_role_order | pressure -> flank -> support -> anchor |
| repeated_role_rule | odd slot: pressure / even slot: flank |

| tactical evidence | strength |
|---|---:|
| visual | 6 |
| enemy_contact | 5 |
| hit | 4 |
| casualty | 4 |
| grenade | 4 |
| attack_sound | 3 |
| enemy_sound | 2 |
| sound | 2 |
| ricochet | 1 |
<!-- END GENERATED: arena-tactics -->

Сила evidence определяет приоритет сведений, а тайминги — скорость их передачи,
старения и anti-stall подсказок. Эти параметры способны существенно менять
фактическую сложность боя даже при неизменной экипировке.

## Автоматическая диагностика

<!-- BEGIN GENERATED: balance-diagnostics -->
| category | diagnostic | value |
|---|---|---|
| fact | minimum_fallback_loadout | 5 budget points |
| derived | rookie max-team feasibility margin | 7 |
| derived | stalker max-team feasibility margin | 20 |
| derived | veteran max-team feasibility margin | 33 |
| derived | master max-team feasibility margin | 40 |
| fact | rookie zero-weight weapon classes | w_sniper |
| fact | rookie zero-weight armor classes | powered_exo |
| derived | rookie -> stalker envelope delta | enemy_budget +25; actor_gear +3; actor_medical +1; enemy_max +2; primary_share +10 pp |
| derived | rookie -> stalker largest weapon-class delta | w_pistol -25 pp |
| derived | rookie -> stalker largest armor-class delta | light -25 pp |
| derived | stalker -> veteran envelope delta | enemy_budget +25; actor_gear +3; actor_medical +1; enemy_max +2; primary_share +15 pp |
| derived | stalker -> veteran largest weapon-class delta | w_rifle +20 pp |
| derived | stalker -> veteran largest armor-class delta | heavy +16 pp |
| derived | veteran -> master envelope delta | enemy_budget +25; actor_gear +2; actor_medical +2; enemy_max +3; primary_share +5 pp |
| derived | veteran -> master largest weapon-class delta | w_rifle +12 pp |
| derived | veteran -> master largest armor-class delta | heavy +10 pp |
| fact | layout capacity versus configured maxima | 10 slots; highest configured maximum 10 |
| derived | capacity-clipped difficulties | none |
| blind_spot | installed merge item cardinality, DPS, penetration, TTK, win rate | runtime measurement |
<!-- END GENERATED: balance-diagnostics -->

Feasibility margin показывает запас общего бюджета после гарантированного
минимального профиля и минимального fallback-комплекта для максимальной команды.
Это проверка конструктивности конфигурации, а не оценка честности боя.

Документ намеренно не выводит единый «balance score». Без измерений win rate,
TTK, дистанции контакта, бронепробития и уровня игрока такой показатель создавал
бы ложную точность.

## Карта источников

<!-- BEGIN GENERATED: source-map -->
| concern | authoritative source |
|---|---|
| player class weights and enemy envelopes | `gamma_arena_difficulties.ltx` |
| fallback items and costs | `gamma_arena_catalogs.ltx` |
| custom threats, budgets, physical cap, and grenade pricing | `gamma_arena_custom_rules.ltx` |
| installed custom combat categories | `gamma_arena_item_catalog.script` |
| installed item classification and class costs | `gamma_arena_catalog_discovery.script` |
| actor/opponent random selection and budget allocation | `gamma_arena_random_generator.script` |
| actor and enemy medical allocation | `gamma_arena_medical_generator.script` |
| grenade probabilities and participant pools | `gamma_arena_grenade_generator.script`; `gamma_arena_catalogs.ltx` |
| actor lighting-device probabilities and selection | `gamma_arena_device_generator.script`; `gamma_arena_catalogs.ltx` |
| physical NPC medicine use | `gamma_arena_npc_medical.script` |
| faction profiles and effective weapon pools | `gamma_arena_catalog.script` |
| powered exo full-charge transaction | `gamma_arena_bootstrap.script` |
| spawn capacity and separation | `gamma_arena_layouts.ltx` |
| tactical timings | `gamma_arena_tactical.ltx` |
| tactical roles and evidence strength | `gamma_arena_tactical_director.script` |
<!-- END GENERATED: source-map -->

Полные production-источники:

- [сложности](../src/gamedata/configs/gamma_arena/gamma_arena_difficulties.ltx);
- [fallback-каталог](../src/gamedata/configs/gamma_arena/gamma_arena_catalogs.ltx);
- [раскладка](../src/gamedata/configs/gamma_arena/gamma_arena_layouts.ltx);
- [тактические настройки](../src/gamedata/configs/gamma_arena/gamma_arena_tactical.ltx);
- [обнаружение installed-каталога](../src/gamedata/scripts/gamma_arena_catalog_discovery.script);
- [загрузка каталога](../src/gamedata/scripts/gamma_arena_catalog.script);
- [генератор боя](../src/gamedata/scripts/gamma_arena_generator.script);
- [тактический директор](../src/gamedata/scripts/gamma_arena_tactical_director.script).

## Цикл настройки баланса

1. Изменить authoritative production-конфиг или правило.
2. Согласованно обновить его schema/revision, fallback manifest и golden fixtures,
   если этого требует изменённый контракт.
3. Перегенерировать этот документ.
4. Проверить diff: числа должны объясняться изменением источника.
5. Запустить `tools/Test-GammaArena.ps1`.
6. Собрать runtime sample: состав комплектов, исход боя, TTK, дистанция первого
   контакта и причина смерти.
7. Отделить наблюдение от гипотезы и только затем менять следующий параметр.

Автоматически поддерживается конфигурационная картина. Реальная боевая
эффективность конкретных installed-предметов остаётся предметом игровых
измерений.
