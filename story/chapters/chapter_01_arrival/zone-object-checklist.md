# Zone 物件清單（Chapter 1）

> **用途**：場景設計人對照此清單擺放物件。每個 zone 列出所有需要的 prop 和 NPC。
> **來源**：`story/chapters/chapter_01_arrival/draft.md` + `assets.md` + zone YAML + 場景氛圍想像
> **狀態**：✅ = 已有 .tscn　🔲 = 需要生成

---

## zone_market（1983）— 熱鬧的傳統市場

### 建築

| # | 物件 | .tscn | 狀態 | 說明 |
|---|---|---|---|---|
| 1 | 榮昌中藥行 | `pharmacy_rongchang_1983.tscn` | ✅ | 金字招牌、紅燈籠 |
| 2 | 閩南街屋 | `market_shophouse_minnan.tscn` | ✅ | ×1-2，市場主建築 |
| 3 | 水泥街屋 | `market_shophouse_concrete.tscn` | ✅ | ×1-2，市場副建築 |

### 攤位 & 商業

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 4 | 菜攤 | `vegetable_stall.tscn` | ✅ | 3 | 阿桃姨攤 + 其他 |
| 5 | 竹編菜籃 | `market_basket_produce.tscn` | ✅ | 3-5 | 攤位旁散放 |
| 6 | 遮雨棚 | `market_awning.tscn` | ✅ | 2-3 | 攤位上方遮陽 |
| 7 | 肉攤掛鉤 | `meat_hook_rack.tscn` | 🔲 | 1 | 鐵架掛肉，1983 傳統市場標誌 |
| 8 | 魚攤冰箱 | `fish_stall_icebox.tscn` | 🔲 | 1 | 保麗龍箱＋碎冰＋魚，市場氣味 |
| 9 | 豆腐攤 | `tofu_stall_bucket.tscn` | 🔲 | 1 | 塑膠桶裝豆腐＋木板，台味小攤 |
| 10 | 秤重磅秤 | `market_scale_hanging.tscn` | 🔲 | 1-2 | 吊掛式彈簧秤，攤位旁 |

### 裝飾 & 氛圍

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 11 | 紅燈籠 | `lantern_paper_red.tscn` | ✅ | 3 | 店門口 |
| 12 | 塑膠椅 | `plastic_chair_red.tscn` | ✅ | 2-3 | 攤位旁休息 |
| 13 | 摩托車 | `motorcycle_parked.tscn` | ✅ | 1-2 | 街角停放 |
| 14 | 木凳 | `wooden_stool_old.tscn` | ✅ | 1-2 | 路邊 |
| 15 | 電線桿 | `power_pole_wooden.tscn` | 🔲 | 1-2 | 木頭電線桿＋纏繞電線，1983 街景 |
| 16 | 布條招牌 | `banner_cloth_sale.tscn` | 🔲 | 1-2 | 紅底白字手寫布條，掛在店門口「大特價」 |
| 17 | 垃圾桶 | `trash_bin_green.tscn` | 🔲 | 1-2 | 綠色鐵皮垃圾桶，市場角落 |
| 18 | 水管水龍頭 | `water_faucet_wall.tscn` | 🔲 | 1 | 牆邊水龍頭＋水漬，攤販洗菜用 |
| 19 | 堆疊紙箱 | `cardboard_boxes_stack.tscn` | 🔲 | 2-3 | 棕色紙箱堆放，市場後巷感 |
| 20 | 腳踏車 | `bicycle_parked.tscn` | 🔲 | 1 | 舊腳踏車靠牆停，菜籃前掛 |
| 21 | 報紙攤 | `newspaper_stand.tscn` | 🔲 | 1 | 鐵架＋疊報紙，1983 年代感 |
| 22 | 電話亭 | `phone_booth_green.tscn` | 🔲 | 1 | 綠色公共電話亭，1983 通訊標誌 |

### NPC

| # | 物件 | 類型 | 狀態 | 說明 |
|---|---|---|---|---|
| 23 | 阿桃姨 | BaseNPC | ✅ | 可互動，菜攤老闆 |
| 24 | 老男攤販 | Sprite2D | ✅ | 背景路人 |
| 25 | 女攤販 | Sprite2D | ✅ | 背景路人 |
| 26 | 女顧客 | Sprite2D | ✅ | 背景路人 |
| 27 | 男路人 | Sprite2D | ✅ | 背景路人 |

---

## zone_market（現代）— 衰落冷清的市場

### 建築

| # | 物件 | .tscn | 狀態 | 說明 |
|---|---|---|---|---|
| 1 | 藥行現代版 | `pharmacy_rongchang_modern.tscn` | ✅ | 鏽門深鎖 |
| 2 | 閩南街屋 | `market_shophouse_minnan.tscn` | ✅ | 老舊褪色 |
| 3 | 水泥街屋 | `market_shophouse_concrete.tscn` | ✅ | ×1-2 |
| 4 | 鏽鐵門 | `iron_gate_rusted.tscn` | ✅ | 藥行入口 |

### 衰落氛圍

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 5 | 殘留菜攤 | `vegetable_stall.tscn` | ✅ | 1 | 唯一還在的攤位 |
| 6 | 木凳 | `wooden_stool_old.tscn` | ✅ | 1-2 | 老周的凳子 |
| 7 | 關閉鐵捲門 | `shutter_closed_rusty.tscn` | 🔲 | 2-3 | 鏽蝕拉下的鐵捲門，暗示店面倒閉 |
| 8 | 褪色招牌 | `sign_faded_old.tscn` | 🔲 | 1-2 | 掉漆的舊招牌，文字模糊 |
| 9 | 堆疊紙箱（破舊） | `cardboard_boxes_torn.tscn` | 🔲 | 1-2 | 濕爛紙箱，被棄置 |
| 10 | 生鏽腳踏車 | `bicycle_rusted.tscn` | 🔲 | 1 | 鏽蝕腳踏車倒在牆邊 |
| 11 | 告示牌（都更） | `notice_board_urban.tscn` | 🔲 | 1 | 「都市更新計畫」公告，現代感 |
| 12 | 機車（現代） | `scooter_modern.tscn` | 🔲 | 1 | 現代白色機車，對比 1983 |

### NPC

| # | 物件 | 類型 | 狀態 | 說明 |
|---|---|---|---|---|
| 13 | 老周 | BaseNPC | ✅ | 可互動，市場入口耆老 |

---

## zone_pharmacy（1983）— 運作中的中藥行

### 藥行設備

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 1 | 木櫃台 | `shop_counter_wood.tscn` | ✅ | 1 | 銅秤+算盤+處方紙 |
| 2 | 新藥櫃 | `medicine_cabinet_new.tscn` | ✅ | 3 | 銅把手、手寫紙標籤 |
| 3 | 國泰日曆 | `cathay_calendar_1983.tscn` | ✅ | 1 | 時代感標誌 |
| 4 | 藥材罐 | `herb_jar_ceramic.tscn` | 🔲 | 3-5 | 陶瓷藥罐，寫著藥材名，排列在櫃上 |
| 5 | 藥材秤 | `herb_scale_brass.tscn` | 🔲 | 1 | 小銅秤＋砝碼，配藥用 |
| 6 | 處方箋 | `prescription_paper_stack.tscn` | 🔲 | 1 | 一疊手寫處方紙，櫃台上 |
| 7 | 研磨缽 | `mortar_pestle_stone.tscn` | 🔲 | 1 | 石製研磨器，磨藥材用 |
| 8 | 曬藥盤 | `herb_drying_tray.tscn` | 🔲 | 1-2 | 竹編淺盤晾曬藥材 |

### 家庭 & 關鍵道具

| # | 物件 | .tscn | 狀態 | 說明 |
|---|---|---|---|---|
| 9 | 塗黑全家福 | `family_photo_blacked.tscn` | ✅ | **關鍵道具**（cutscene 鏡頭對準） |
| 10 | 木凳 | `wooden_stool_old.tscn` | ✅ | ×2，客人等候 |
| 11 | 紅燈籠 | `lantern_paper_red.tscn` | ✅ | ×2，藥行門口 |
| 12 | 銅香爐 | `incense_burner_brass.tscn` | ✅ | 供奉用 |
| 13 | 神明桌 | `altar_table_wood.tscn` | 🔲 | 1 | 木製神明桌＋香爐＋供品，台灣家庭必備 |
| 14 | 茶壺茶杯 | `tea_set_ceramic.tscn` | 🔲 | 1 | 陶瓷茶壺＋小杯，櫃台旁招待客人 |
| 15 | 收音機 | `radio_old_brown.tscn` | 🔲 | 1 | 棕色老收音機，播放 1983 年廣播 |
| 16 | 掛鐘 | `wall_clock_round.tscn` | 🔲 | 1 | 圓形掛鐘，滴答聲 |

### NPC

| # | 物件 | 類型 | 狀態 | 說明 |
|---|---|---|---|---|
| 17 | 林榮昌 | BaseNPC | ✅ | 櫃台後方 |
| 18 | 陳秀琴 | BaseNPC | ✅ | 櫃台旁 |
| 19 | 林阿嬤 | BaseNPC | ✅ | 東側 |
| 20 | 林小威 | BaseNPC | ✅ | 南側 |

---

## zone_pharmacy（現代）— 廢棄 40 年的藥行

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 1 | 鏽鐵門 | `iron_gate_rusted.tscn` | ✅ | 1 | 入口 |
| 2 | 木櫃台 | `shop_counter_wood.tscn` | ✅ | 1 | 積灰 |
| 3 | 積灰藥櫃 | `medicine_cabinet_dusty.tscn` | ✅ | 3 | 蛛網、40 年灰塵 |
| 4 | 塗黑全家福 | `family_photo_blacked.tscn` | ✅ | 1 | **關鍵道具** |
| 5 | 銅香爐 | `incense_burner_brass.tscn` | ✅ | 1 | |
| 6 | 古地圖 | `old_map_paper.tscn` | ✅ | 1 | **關鍵道具** |
| 7 | 蛛網 | `cobweb_corner.tscn` | 🔲 | 2-3 | 角落蛛網，廢棄感 |
| 8 | 落灰布 | `dusty_cloth_cover.tscn` | 🔲 | 1-2 | 蓋在傢俱上的灰布 |
| 9 | 破碎藥罐 | `herb_jar_broken.tscn` | 🔲 | 1-2 | 碎裂的藥罐散落地上 |
| 10 | 老舊燈泡 | `light_bulb_hanging.tscn` | 🔲 | 1 | 懸吊裸燈泡，穿越觸發時閃爍 |

---

## zone_pharmacy_backyard（1983）— 藥行後院，秘密之地

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 1 | 銅香爐 | `incense_burner_brass.tscn` | ✅ | 1 | 阿嬤燒香處（cutscene） |
| 2 | 紅燈籠 | `lantern_paper_red.tscn` | ✅ | 2 | |
| 3 | 上鎖鐵門 | `iron_gate_rusted.tscn` | ✅ | 1 | 林榮華房間入口 |
| 4 | 皮革筆記本 | `notebook_leather.tscn` | ✅ | 1 | **關鍵道具** |
| 5 | 舊鋼筆 | `fountain_pen_old.tscn` | ✅ | 1 | 遺物候選 |
| 6 | 黑白照片 | `photograph_old.tscn` | ✅ | 1 | 遺物候選 |
| 7 | 水井 | `well_stone_old.tscn` | 🔲 | 1 | 石砌水井，後院標誌 |
| 8 | 晾衣架 | `clothesline_bamboo.tscn` | 🔲 | 1 | 竹竿晾衣架＋幾件衣服，生活感 |
| 9 | 盆栽 | `potted_plant_clay.tscn` | 🔲 | 2-3 | 陶盆種的草藥/萬年青 |
| 10 | 掃帚畚箕 | `broom_dustpan.tscn` | 🔲 | 1 | 竹掃帚＋畚箕靠牆，暗示林榮昌打掃 |
| 11 | 舊木門 | `door_wooden_locked.tscn` | 🔲 | 1 | 林榮華房間的木門（視覺上鎖） |
| 12 | 老舊書桌 | `desk_wooden_old.tscn` | 🔲 | 1 | 房間內書桌（放遺物） |
| 13 | 單人床 | `bed_single_old.tscn` | 🔲 | 1 | 林榮華的床，整齊但無人睡 |
| 14 | 牆上剪報 | `newspaper_clipping_wall.tscn` | 🔲 | 2-3 | 泛黃剪報貼牆上，暗示 1976 事件 |
| | **NPC** | | | | |
| 15 | 林阿嬤 | BaseNPC | ✅ | 1 | 燒香場景 |

---

## zone_apartment_muzha（現代）— 阿謙的臨時住處

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 1 | 老公寓 | `old_apartment_muzha.tscn` | ✅ | 1 | 建築外觀 |
| 2 | 父親身分證 | `id_card_old.tscn` | ✅ | 1 | **關鍵道具** |
| 3 | 舊照片 | `photograph_old.tscn` | ✅ | 1 | 父親遺物 |
| 4 | 筆記本 | `notebook_leather.tscn` | ✅ | 1 | 父親遺物 |
| 5 | 鋼筆 | `fountain_pen_old.tscn` | ✅ | 1 | 父親遺物 |
| 6 | 行李箱 | `suitcase_travel.tscn` | 🔲 | 1 | 阿謙的行李箱，剛搬來 |
| 7 | 筆電 | `laptop_modern.tscn` | 🔲 | 1 | 阿謙的筆電，平面設計師 |
| 8 | 咖啡杯 | `coffee_mug.tscn` | 🔲 | 1 | 桌上咖啡杯，現代生活感 |
| 9 | 紙箱（搬家） | `moving_box_taped.tscn` | 🔲 | 2-3 | 封箱膠帶貼好的紙箱，剛搬來 |
| 10 | 摺疊桌 | `folding_table.tscn` | 🔲 | 1 | 簡易摺疊桌，臨時住所 |
| 11 | 律師信 | `letter_envelope.tscn` | 🔲 | 1 | 桌上的信封，繼承通知 |
| 12 | 手機充電器 | `phone_charger.tscn` | 🔲 | 1 | 現代感小物 |

---

## zone_law_office（現代）— 老牌律師事務所

| # | 物件 | .tscn | 狀態 | 數量 | 說明 |
|---|---|---|---|---|---|
| 1 | 律師事務所 | `law_office_muzha.tscn` | ✅ | 1 | 建築 |
| 2 | 木櫃台 | `shop_counter_wood.tscn` | ✅ | 1 | 辦公桌 |
| 3 | 筆記本 | `notebook_leather.tscn` | ✅ | 1 | 繼承文件 |
| 4 | 書架 | `bookshelf_law.tscn` | 🔲 | 1-2 | 法律書籍排列，專業感 |
| 5 | 檔案櫃 | `filing_cabinet_metal.tscn` | 🔲 | 1 | 鐵製檔案櫃，存放文件 |
| 6 | 桌燈 | `desk_lamp_brass.tscn` | 🔲 | 1 | 黃銅桌燈，律師辦公桌 |
| 7 | 掛鐘 | `wall_clock_round.tscn` | 🔲 | 1 | 辦公室掛鐘 |
| 8 | 盆栽 | `potted_plant_office.tscn` | 🔲 | 1 | 辦公室植物 |
| 9 | 證書框 | `certificate_frame.tscn` | 🔲 | 1-2 | 牆上律師證書/執照 |
| | **NPC** | | | | |
| 10 | 陳律師 | BaseNPC | ✅ | 1 | 可互動 |

---

## 通用（兩個時代都顯示，不加 era group）

| 物件 | .tscn | 狀態 | 用途 |
|---|---|---|---|
| 傳送點木牌 | `hanging_wood_sign.tscn` | ✅ | 放在每個 ZoneTransitionArea 旁 |

---

## 需要生成的新物件總覽（🔲）

### 市場類（1983）
| 名稱 | 描述（給 Pixellab） | 尺寸 |
|---|---|---|
| `meat_hook_rack` | iron meat hook rack with hanging pork cuts, traditional taiwanese market butcher stall | 48 |
| `fish_stall_icebox` | styrofoam icebox with crushed ice and fresh fish, traditional market seafood stall | 48 |
| `tofu_stall_bucket` | plastic bucket with soft tofu and wooden cutting board, simple taiwanese market stall | 32 |
| `market_scale_hanging` | hanging spring scale with metal hook and round dial, market weighing tool | 24 |
| `power_pole_wooden` | old wooden power pole with tangled electric wires, 1980s taiwanese street | 48 |
| `banner_cloth_sale` | red cloth banner with white hand-painted chinese sale text, hung between poles | 32 |
| `trash_bin_green` | green painted iron trash bin, dented and worn, street corner | 24 |
| `water_faucet_wall` | wall-mounted water faucet with wet puddle below, outdoor market washing area | 24 |
| `cardboard_boxes_stack` | stacked brown cardboard boxes in market alley, some opened | 32 |
| `bicycle_parked` | old black bicycle with front wire basket, leaning against wall, 1980s style | 48 |
| `newspaper_stand` | iron newspaper rack with stacked daily newspapers, 1983 taiwan street | 32 |
| `phone_booth_green` | green public phone booth, 1980s taiwan municipal style | 48 |

### 現代衰落類
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `shutter_closed_rusty` | rusty closed metal rolling shutter door, abandoned shop front | 64 |
| `sign_faded_old` | old faded shop sign with peeling paint and unreadable text | 32 |
| `cardboard_boxes_torn` | torn wet cardboard boxes abandoned on ground, urban decay | 32 |
| `bicycle_rusted` | rusted old bicycle fallen on its side against wall | 48 |
| `notice_board_urban` | government urban renewal notice board on metal stand | 32 |
| `scooter_modern` | modern white motor scooter parked, sleek design | 48 |

### 藥行內部類
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `herb_jar_ceramic` | traditional chinese medicine ceramic jar with handwritten label | 24 |
| `herb_scale_brass` | small brass balance scale with weights, chinese pharmacy tool | 24 |
| `prescription_paper_stack` | stack of handwritten chinese medicine prescription papers | 16 |
| `mortar_pestle_stone` | stone mortar and pestle for grinding herbs, traditional pharmacy | 24 |
| `herb_drying_tray` | shallow bamboo tray with dried herbs spread out for drying | 32 |
| `altar_table_wood` | small wooden altar table with incense holder and offering plate, taiwanese home | 48 |
| `tea_set_ceramic` | ceramic teapot with small cups on round wooden tray | 24 |
| `radio_old_brown` | brown vintage radio with round dial and speaker grille, 1980s | 24 |
| `wall_clock_round` | round wall clock with white face and black numbers | 24 |

### 廢棄藥行類（現代）
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `cobweb_corner` | spider cobweb in corner with dust, abandoned building detail | 16 |
| `dusty_cloth_cover` | grey dusty cloth draped over furniture, abandoned room | 32 |
| `herb_jar_broken` | broken ceramic medicine jar pieces scattered on floor | 24 |
| `light_bulb_hanging` | single bare light bulb hanging from wire, dim and dusty | 16 |

### 後院類
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `well_stone_old` | old stone well with wooden bucket and rope, overgrown with moss | 48 |
| `clothesline_bamboo` | bamboo pole clothesline with a few hanging clothes and towels | 48 |
| `potted_plant_clay` | clay pot with green herbs or wan-nian-qing plant, traditional taiwanese courtyard | 24 |
| `broom_dustpan` | bamboo broom and metal dustpan leaning against wall | 24 |
| `door_wooden_locked` | old wooden door with brass padlock, locked and mysterious | 48 |
| `desk_wooden_old` | old wooden writing desk with drawer, simple and worn | 48 |
| `bed_single_old` | single bed with folded blanket, neat but unused for years | 48 |
| `newspaper_clipping_wall` | yellowed newspaper clippings pinned to wall, 1976 era news | 16 |

### 公寓類（現代）
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `suitcase_travel` | modern rolling suitcase, dark grey, just arrived | 32 |
| `laptop_modern` | modern laptop computer on desk, screen glowing, designer workspace | 32 |
| `coffee_mug` | white coffee mug with steam, on desk | 16 |
| `moving_box_taped` | sealed cardboard moving box with packing tape, freshly moved | 32 |
| `folding_table` | simple folding table, lightweight, temporary living | 32 |
| `letter_envelope` | formal letter envelope with law firm stamp, opened | 16 |

### 律師事務所類
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `bookshelf_law` | tall wooden bookshelf filled with law books and binders | 64 |
| `filing_cabinet_metal` | grey metal filing cabinet with label slots, office furniture | 48 |
| `desk_lamp_brass` | brass desk lamp with green glass shade, classic lawyer office | 24 |
| `potted_plant_office` | small office plant in white ceramic pot, ficus or peace lily | 24 |
| `certificate_frame` | framed certificate or license on wall, gold border | 24 |

### 第二波：市場街景生活
| 名稱 | 描述（給 Pixellab） | 尺寸 |
|---|---|---|
| `vendor_cart_wood` | wooden two-wheel vendor push cart with fruits displayed on top, traditional taiwanese market | 48 |
| `ice_cream_cart` | taiwanese ba-bu ice cream push cart with colorful umbrella on top, 1980s street food | 48 |
| `rice_sack_stack` | stacked burlap rice sacks with red printed chinese text, grain shop | 32 |
| `oil_drum_metal` | large metal cooking oil drum, industrial, grocery store side | 32 |
| `bamboo_steamer` | stacked bamboo steam baskets with steam rising, bun stall | 24 |
| `neon_sign_shop` | colorful neon tube shop sign, chinese characters glowing, 1980s commercial | 32 |
| `fire_hydrant_red` | red fire hydrant on street corner, taiwanese municipal | 24 |
| `mailbox_green` | green chinese postal mailbox, chunghwa post, 1980s taiwan street | 32 |
| `stray_cat_sleeping` | sleeping stray tabby cat curled on cardboard box, market alley | 16 |
| `stray_dog_sitting` | stray dog sitting and watching passersby, friendly face, market | 24 |

### 第二波：中藥行文化
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `abacus_wood` | wooden chinese abacus with black beads on desk, traditional calculation tool | 16 |
| `herb_drawer_label` | chinese medicine drawer with handwritten herb name label, close-up detail | 24 |
| `medicine_bag_paper` | brown kraft paper medicine bag, wrapped and tied, traditional pharmacy | 16 |
| `deity_statue_small` | small guan gong or mazu deity statue, painted ceramic, shop altar | 24 |
| `lucky_cat_ceramic` | ceramic maneki-neko lucky cat with raised paw, shop counter decoration | 16 |
| `couplet_door_red` | red door couplet with gold chinese calligraphy, spring festival decoration | 32 |

### 第二波：後院 & 現代對比
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `chicken_coop_small` | small wooden chicken coop with wire mesh and a few chickens, backyard | 32 |
| `rain_barrel_wood` | wooden rain barrel for collecting rainwater, backyard utility | 24 |
| `stone_bench_garden` | stone garden bench, simple, courtyard seating | 32 |
| `herb_garden_patch` | small herb garden patch with planted medicinal herbs, raised bed | 32 |
| `washing_board_wood` | wooden washboard with water basin, traditional laundry, 1980s | 24 |
| `cctv_camera_pole` | CCTV security camera mounted on pole, modern surveillance | 24 |
| `led_sign_modern` | LED scrolling text sign board, modern shop front | 32 |
| `vending_machine` | japanese style drink vending machine, lit up, modern street | 48 |
| `recycling_bin_set` | set of colored recycling bins, blue yellow green, modern urban | 32 |
| `air_conditioner_unit` | window air conditioner outdoor unit mounted on wall bracket | 24 |

### 第二波：公寓 & 雜項
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `wifi_router_sign` | free wifi sign on stand, modern commercial area | 16 |
| `mattress_floor` | thin floor mattress with pillow, laid on ground, temporary sleeping | 32 |
| `water_bottle_plastic` | large plastic water bottle on floor, daily necessity | 16 |
| `photo_frame_family` | small photo frame with family photo, father and son, on desk | 16 |
| `backpack_travel` | travel backpack on floor, dark grey, zippers and straps | 24 |
| `sticky_notes_wall` | colorful sticky notes pinned to wall with handwritten clues and questions | 16 |
| `weighing_platform` | flat metal weighing platform scale for heavy goods, market wholesale | 32 |

### 第三波：台灣小吃 & 飲食
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `wonton_soup_pot` | large pot of wonton soup or braised food, steaming, market food stall | 32 |
| `tea_egg_pot` | tea egg pot with dark soy broth and eggs floating, convenience stall | 24 |
| `sugarcane_juice_press` | sugarcane juice press machine, green iron frame, sugarcane sticks inserted | 48 |
| `shaved_ice_machine` | shaved ice machine with colorful syrup bottles lined up, summer treat stall | 32 |
| `soy_milk_bucket` | soy milk bucket with ladle, traditional breakfast stall | 24 |
| `rice_cooker_big` | classic green tatung rice cooker, taiwanese household icon | 24 |
| `cutting_board_meat` | thick wooden cutting board with cleaver stuck in, butcher detail | 16 |
| `plastic_bag_hanging` | bunch of red-white striped plastic bags hanging on hook, market essential | 16 |

### 第三波：宗教 & 民俗
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `temple_lantern_stone` | stone carved palace lantern, temple roadside decoration | 32 |
| `joss_paper_stack` | stack of gold and silver joss paper ready to burn, religious offering | 16 |
| `offering_fruit_plate` | fruit offering plate with apples oranges and pineapple, altar decoration | 24 |
| `fortune_stick_box` | bamboo fortune stick container with fortune poems, temple divination tool | 24 |
| `door_god_poster` | door god new year poster, painted warrior, on door panel | 32 |
| `bagua_mirror` | octagonal bagua mirror hung above door, feng shui protection charm | 16 |

### 第三波：交通 & 基礎設施
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `bus_stop_sign` | bus stop sign on iron pole with route number plate, taiwanese municipal | 48 |
| `manhole_cover_round` | round cast iron manhole cover with decorative pattern, street ground | 16 |
| `drainage_grate` | long rectangular drainage grate cover, market ground, wet | 24 |
| `utility_box_green` | green electrical utility box on street side, municipal infrastructure | 32 |
| `street_number_plate` | blue door number plate with white digits, taiwanese building identification | 16 |

### 第三波：生活痕跡 & 故事暗示
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `calendar_torn_page` | wall calendar with some pages torn off, stopped on a specific date | 16 |
| `cigarette_ashtray` | glass ashtray with cigarette butts, desk or counter top | 16 |
| `umbrella_stand` | umbrella stand with a few folded umbrellas, shop entrance | 24 |
| `slippers_pair` | pair of blue-white taiwanese flip flops at doorstep | 16 |
| `key_ring_wall` | wall hook with a ring of old keys hanging, hints at locked room | 16 |
| `old_tv_box` | old CRT television set with rabbit ear antenna, wooden frame, 1980s | 32 |
| `fan_standing` | standing oscillating fan with iron mesh guard, no AC era | 32 |
| `thermos_flask` | stainless steel thermos with floral pattern, taiwanese grandma essential | 16 |

### 第三波：自然 & 環境
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `banyan_tree_small` | small banyan tree with aerial roots hanging down, tropical taiwanese street tree | 64 |
| `puddle_water` | small water puddle on ground, reflective surface, after rain | 16 |
| `moss_patch_wall` | green moss patch growing on wall corner, damp abandoned building | 16 |
| `weed_crack_ground` | weeds growing through cracked ground, urban decay detail | 16 |
| `vine_wall_climbing` | green climbing vine on wall, creeping plant, overgrown | 32 |

### 第三波：互動暗示道具
| 名稱 | 描述 | 尺寸 |
|---|---|---|
| `locked_box_wood` | small locked wooden box with scratch marks, mysterious container | 24 |
| `letter_hidden_drawer` | half-open drawer with envelope corner peeking out, secret document hint | 16 |
| `footprint_dust` | footprints in dusty floor, someone has been here recently | 16 |
| `scratch_mark_door` | height measurement scratch marks on door frame, child growth marks | 16 |

---

## 所有 .tscn 位置

```
res://src/maps/props/<name>.tscn
```

### 工作流程

1. Dashboard 生成 PNG → `art_source/objects/<name>/<name>.png`
2. 跑 `uv run python scripts/sync_props.py` 自動產出 .tscn
3. Godot `Ctrl+Shift+R` → 拖 .tscn 到 `YSortRoot` → 設 group → 調位置 → `Ctrl+S`

### 物件總數

| 波次 | 數量 | 狀態 |
|---|---|---|
| 原始資產 | ~25 | ✅ |
| 第一波（氛圍補充） | 47 | ✅ |
| 第二波（街景生活） | 33 | 生成中 |
| 第三波（文化深度） | 39 | 生成中 |
| **總計** | **~144** | |
