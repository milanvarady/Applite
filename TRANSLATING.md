# Translating Applite

Applite ships in English plus Hungarian, French, Japanese, Simplified Chinese, Traditional Chinese
(Hong Kong) and Turkish. Everything lives in `Localizable.xcstrings`; English is the source language
and the key.

This file is the **glossary**: the agreed rendering of the words that recur across the UI. Look a
term up here before translating a string that contains it — a small app feels wrong much faster from
calling the same button three different things than from any single awkward sentence.

## Register

Not a matter of taste — this is what the existing translations already established, and new strings
must match:

| | Register | Buttons |
|---|---|---|
| **hu** | formal (magázás) — *"Biztos véglegesen törli?"* | nominal: *Telepítés*, not *Telepítsd* |
| **fr** | vouvoiement | infinitive: *Installer*. Narrow no-break space before `!` `?` `:` |
| **ja** | です／ます | noun form; progress labels take *…中* |
| **zh-Hans / zh-HK** | 你, not 您 (Apple's current style) | space between CJK and Latin/digits |
| **tr** | formal *-iniz* | sentence case |

## Glossary

Values marked **Apple** were read out of the localization tables macOS itself ships — see
[Method](#method). Where Applite deviates, the reason is given below the table; a deviation needs a
reason, and "I'd have said it differently" isn't one.

### Actions

| Term | hu | fr | ja | zh-Hans | zh-HK | tr |
|---|---|---|---|---|---|---|
| Install | Telepítés | Installer | インストール | 安装 | 安裝 | Yükle |
| Reinstall ¹ | Újratelepítés | Réinstaller | 再インストール | 重新安装 | 重新安裝 | Yeniden Yükle |
| Uninstall | Eltávolítás | Désinstaller | アンインストール | 卸载 | 解除安裝 | Yüklemeyi Kaldır |
| Update | Frissítés | Mettre à jour | アップデート | 更新 | 更新 | Güncelle |
| Refresh | Frissítés | Actualiser | 更新 | 刷新 | 重新整理 | Yenile |
| Download | Letöltés | Télécharger | ダウンロード | 下载 | 下載 | İndir |
| Import | Importálás | Importer | 読み込む | 导入 | 匯入 ² | İçe Aktar |
| Export | Exportálás | Exporter | 書き出す | 导出 | 匯出 ² | Dışa Aktar |
| Open | Megnyitás | Ouvrir | 開く | 打开 | 開啟 | Aç |
| Copy | Másolás | Copier | コピー | 拷贝 | 複製 | Kopyala |
| Delete | Törlés | Supprimer | 削除 | 删除 | 刪除 | Sil |
| Remove | Eltávolítás | Supprimer | 削除 | 移除 | 移除 | Kaldır |
| Stop | Leállítás | Arrêter | 停止 | 停止 | 停止 | Durdur |
| Cancel | Mégsem | Annuler | キャンセル | 取消 | 取消 | Vazgeç |
| Retry | Újra | Réessayer | 再試行 | 重试 | 再試 | Yeniden Dene |
| Try Again | Újrapróbálkozás | Réessayer | やり直す | 重试 | 再試 | Yeniden Dene |
| Continue | Folytatás | Continuer | 続ける | 继续 | 繼續 | Sürdür |
| Select All | Összes kijelölése | Tout sélectionner | すべてを選択 | 全选 | 全選 | Tümünü Seç |
| Deselect All | Kijelölés megszüntetése ³ | Tout désélectionner | すべてを選択解除 | 取消全选 | 取消全選 | Seçimi Kaldır |
| Dismiss / Close | Bezárás | Fermer | 閉じる | 关闭 | 關閉 | Kapat |
| Search | Keresés | Rechercher | 検索 | 搜索 | 搜尋 | Ara |
| Done | Kész | Terminé | 完了 | 完成 | 完成 | Bitti |

### States

| Term | hu | fr | ja | zh-Hans | zh-HK | tr |
|---|---|---|---|---|---|---|
| Installed | Telepítve | Installée | インストール済み | 已安装 | 已安裝 | Yüklü |
| Not installed | Nincs telepítve | Non installée | 未インストール | 未安装 | 未安裝 | Yüklü değil |
| Enabled | Bekapcsolva | Activée | 有効 | 已启用 | 已啟用 | Etkin |
| Disabled | Letiltva | Désactivée | 無効 | 已停用 | 已停用 | Etkin değil |
| Outdated | Elavult | Obsolète | アップデートあり | 有可用更新 | 有可用更新 | Güncel değil |
| Deprecated | Elavult | Obsolète | 非推奨 | 已弃用 | 已棄用 | Artık önerilmiyor |
| Failed | Sikertelen | Échec | 失敗 | 失败 | 失敗 | Başarısız |

Adjectives in French agree with **l'application** (feminine): *Installée*, *Activée*, *Désactivée*.

### Sections and nouns

| Term | hu | fr | ja | zh-Hans | zh-HK | tr |
|---|---|---|---|---|---|---|
| Settings | Beállítások | Réglages | 設定 | 设置 | 設定 | Ayarlar |
| General | Általános | Général | 一般 | 通用 | 一般 | Genel |
| Advanced | Haladó | Avancé | 詳細 | 高级 | 進階 | İleri Düzey |
| Options | Beállítások | Options | オプション | 选项 | 選項 | Seçenekler |
| Categories | Kategóriák | Catégories | カテゴリ | 分类 ⁴ | 分類 ⁴ | Kategoriler |
| Utilities | Segédprogramok ⁵ | Utilitaires | ユーティリティ | 实用工具 ⁵ | 工具程式 ⁵ | İzlenceler |
| Applications / Apps | Alkalmazások | Applications | アプリ | 应用 | 應用程式 | Uygulamalar |
| Version | Verzió | Version | バージョン | 版本 | 版本 | Sürüm |
| Date | Dátum | Date | 日付 | 日期 | 日期 | Tarih |
| File | Fájl | Fichier | ファイル | 文件 | 檔案 | Dosya |
| Path | Útvonal | Chemin | パス | 路径 | 路徑 | Yol |
| Cache | Gyorsítótár | Cache | キャッシュ | 缓存 | 快取 | Önbellek |
| System | Rendszer | Système | システム | 系统 | 系統 | Sistem |
| Terminal | Terminál | Terminal | ターミナル | 终端 | 終端機 | Terminal |
| Output | Kimenet | Sortie | 出力 | 输出 | 輸出 | Çıkış |
| Error | Hiba | Erreur | エラー | 错误 | 錯誤 | Hata |
| Warning | Figyelmeztetés | Avertissement | 警告 | 警告 | 警告 | Uyarı |
| Note ⁶ | Megjegyzés | Remarque | 備考 | 备注 | 備註 | Not |
| Waiting… | Várakozás… | En attente… | 待機中… | 等待中… | 等待中… | Bekleniyor… |

### Homebrew jargon — not Apple's to define

These are Homebrew's own vocabulary. Keep them recognisable: a user who searches the web for help
needs the term to survive translation.

| Term | Treatment |
|---|---|
| Homebrew, Brew | never translated |
| Cask | never translated |
| Tap | kept as a proper noun; pluralised only where natural — hu *Tapek*, tr *Tap'ler*, otherwise *Tap* |
| Token | loanword in hu/fr/tr; ja トークン, zh-Hans 标识符, zh-HK 識別碼 |
| Brewfile | never translated |
| `--appdir`, `--greedy`, `tap`, `brew doctor` | never translated, keep the backticks |

## Deviations from Apple, and why

1. **Reinstall** — Apple ships no "Reinstall" string; each language is derived from its Install form.
2. **Import / Export (zh-HK)** — Apple uses 輸入 / 輸出. Applite also has an **Output** string, which
   is 輸出, so adopting Apple's export term would make Export and Output the same word in the same
   app. 匯入 / 匯出 keeps them apart and is standard in Traditional Chinese software.
3. **Deselect All (hu)** — Apple's most frequent form is *Összes kijelölésének törlése*; this sits
   next to a checkbox in a sheet, so the shorter *Kijelölés megszüntetése* (also Apple's, less
   frequent) is used.
4. **Categories (zh)** — Apple uses 类别/類別. Applite keeps 分类/分類, which is what app stores use
   for browsable categories; 类别 reads as a data field.
5. **Utilities** — Apple's *most frequent* hit is the Launchpad "Other" grouping (*Egyéb*, 更多项目,
   *Diğer*). The **folder** sense is the one Applite means, so its less frequent forms are used.
6. **Note** — Apple's *Jegyzet* / メモ / 筆記 are the Notes **app**. Applite means "remark", as in
   "**Note:** this will…", so it uses *Megjegyzés* / 備考 / 備註.
7. **Sort By (tr)** — Apple's *Şuna Göre Sırala:* overflows the toolbar menu label; shortened to
   *Sırala*.

## Method

The Apple column was not written from memory. macOS ships its localizations as `.loctable` plists —
one file per string table, keyed by language — under `/System/Library/Frameworks`,
`/System/Library/PrivateFrameworks`, `/System/Applications` and `/System/Library/CoreServices`.
For each term, find the keys whose `en` value matches exactly, then read those same keys out of
`hu` / `fr` / `ja` / `zh_CN` / `zh_HK` / `tr`, and count how often each rendering occurs.

Frequency is evidence, not a verdict: the same English word is often several different UI concepts,
which is exactly what notes 4–6 above are about. Always check the alternates before adopting the
top hit.

## Checklist for a new string

- [ ] Every glossary term in it uses the glossary's rendering.
- [ ] Register matches the table at the top.
- [ ] Placeholders (`%@`, `%lld`) all present; reorder with `%1$@` / `%2$@` if the language needs it.
- [ ] Markdown, backticks and line breaks preserved exactly.
- [ ] Counted strings: French inflects after a numeral and needs plural variations. Hungarian and
      Turkish take the bare singular after a number, and Japanese/Chinese have no plural — one form.
- [ ] Buttons and labels stay close to the English length; long descriptions may run as long as
      they need to.
