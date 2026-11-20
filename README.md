# adb-for-arm64

在 Android 手機上直接執行的 **adb（Android Debug Bridge）**，給 ARM64（arm64-v8a）裝置用。
原始碼來自 AOSP 的 [`platform/packages/modules/adb`](https://android.googlesource.com/platform/packages/modules/adb/)，
用 Android NDK 交叉編譯。GitHub Actions 每天檢查一次 AOSP 有沒有新版本，有的話自動編譯並發佈到 [Releases](../../releases)。

有了它，手機開啟「無線偵錯」後，可以在手機上用 adb 連回自己（`adb pair` / `adb connect 127.0.0.1:埠號`），不需要電腦。

## 下載

最新版的執行檔固定在這個網址：

```
https://github.com/ShingWong08/adb-for-arm64/releases/latest/download/adb
```

Releases 頁面有：

| 檔案 | 內容 |
|---|---|
| `adb` | 執行檔本體 |
| `adb-arm64-v8a.zip` | 執行檔 + 所有元件的授權條款 + 編譯資訊 |
| `SHA256SUMS` | 校驗碼 |

系統需求：64 位元 ARM 的 Android 7.0（API 24）以上。
無線偵錯配對（`adb pair`）需要 Android 11 以上。

## 在手機上使用（以 Termux 為例）

```sh
curl -LO https://github.com/ShingWong08/adb-for-arm64/releases/latest/download/adb
chmod +x adb
./adb version
```

想直接打 `adb`，可以把它放進 `$PREFIX/bin`（會跟 Termux 的 `android-tools` 套件衝突，二選一）。

### Wi-Fi 自我調試（Android 11+）

1. 手機連上 Wi-Fi。
2. 開發人員選項 → 開啟「**無線偵錯**」。
3. 點「**使用配對碼配對裝置**」，畫面會顯示 `IP 位址:埠號` 和六位數配對碼。
   這個視窗切到別的 App 時通常會自己關掉，建議用**分割畫面**或**浮動視窗**同時開著終端機。
4. 在終端機配對（埠號用配對視窗上那個）：
   ```sh
   adb pair 127.0.0.1:配對埠號 配對碼
   ```
5. 連線（埠號用「無線偵錯」主畫面上「IP 位址和通訊埠」那個，**跟配對埠號不一樣**）：
   ```sh
   adb connect 127.0.0.1:連線埠號
   adb devices
   adb shell
   ```

配對只需要做一次。之後每次重新開啟無線偵錯，連線埠號會變，重新 `adb connect` 新埠號即可。

### 注意事項

- **沒有 mDNS**：這個版本關閉了 mDNS（自動探索），所以 `adb mdns` 用不了，`adb pair` / `adb connect` 都要手動輸入埠號。
- **需要可寫入的 `HOME` 和 `TMPDIR`**：adb 會把金鑰存在 `$HOME/.android/`，伺服器日誌寫到 `$TMPDIR/adb.<uid>.log`。
  Termux 已經設定好；在其他終端機 App 裡請先設定，例如：
  ```sh
  export HOME=/data/data/<你的終端機 App>/files
  export TMPDIR=$HOME/tmp && mkdir -p $TMPDIR
  ```
  沒有設定 `TMPDIR` 時會用 `/data/local/tmp`（只有 shell/root 身分能寫入）。
- **USB OTG**：沒有 root 的話 App 無法直接存取 USB 裝置。搭配 Termux:API 可以用
  `termux-usb -r -e "adb devices" /dev/bus/usb/…`，adb 會透過 `TERMUX_USB_FD` 取得裝置。

## 自動編譯的運作方式

工作流程在 [`.github/workflows/build.yml`](.github/workflows/build.yml)：

1. **每天 20:00（日本時間，UTC+9）** 執行一次（GitHub 的 cron 用 UTC，所以寫成 `0 11 * * *`）。
2. 讀取 AOSP adb 倉庫所有 `android-X.Y.Z_rN` 標籤，取版本最新的一個。
3. 如果這個標籤指向的 adb commit 已經發佈過（不管是哪個標籤名稱），就什麼都不做。
4. 否則抓取該標籤的 AOSP 原始碼，編譯 arm64-v8a 版，另外用同一份原始碼編譯一個 x86_64 版。
5. **模擬器測試**：開一個 Android 14 x86_64 模擬器，把 adb 放進模擬器裡執行，
   讓它 `adb connect 127.0.0.1:5555` 連回模擬器自己，再跑 `adb shell`、`adb push`，等於在 CI 裡重現「手機自己調試自己」。
   x86_64 版必須通過；arm64 版也會透過模擬器內建的 ARM 轉譯跑同一套測試（結果顯示在 Actions 執行頁面的 annotation）。
   測試腳本是 [`scripts/smoke-test.sh`](scripts/smoke-test.sh)。
6. 測試通過後，以 AOSP 標籤名稱（例如 `android-17.0.0_r1`）建立 Release，只發佈 arm64-v8a 版。

為什麼追標籤而不是 `main`：Google 從 2025 年 3 月起不再公開更新 AOSP 的 `main` 分支，新程式碼只會隨版本標籤（例如 `android-17.0.0_r1`）一次釋出。

手動執行：GitHub 上 **Actions → Build adb → Run workflow**。
- `aosp_ref`：指定要編譯的 AOSP 標籤或分支（留空 = 最新標籤）
- `force`：已經發佈過也重新編譯，並更新該 Release 的檔案

推送到 `main`（修改 `scripts/`、`cmake/`、`patches/` 或工作流程）時也會編譯一次做測試，但只上傳 Artifact，不發佈 Release。

## 編譯流程

| 步驟 | 腳本 | 說明 |
|---|---|---|
| 1 | `scripts/setup-ndk.sh` | 下載固定版本的 Android NDK |
| 2 | `scripts/fetch-sources.sh` | 以指定標籤 clone AOSP 的 adb、libbase、core、logging、libziparchive、boringssl、fmtlib、libusb；套用補丁 |
| 3 | `scripts/build-deps.sh` | 編譯 protobuf（主機用的 protoc + 手機用的靜態庫）、brotli、lz4、zstd |
| 4 | `scripts/build-adb.sh` | 用 CMake + NDK 編譯 adb、strip、檢查動態依賴、打包 |
| 5 | `scripts/publish-release.sh` | 建立或更新 GitHub Release |

版本設定集中在 [`scripts/versions.env`](scripts/versions.env)（NDK、API level、第三方庫版本與 SHA-256）。

產出的 `adb` 只動態連結每台 Android 都有的系統庫（`libc`、`libm`、`libdl`、`libz`），C++ 標準庫和其他依賴都是靜態連結。

### 補丁從哪裡來

- **CMake 編譯清單與通用補丁**：來自 [nmeum/android-tools](https://github.com/nmeum/android-tools)（Alpine、Arch、Termux 等都用它打包 adb）。
  `fetch-sources.sh` 會自動挑選 nmeum/android-tools 裡「釘選同一個 adb commit」的最新 commit，取用它的 `vendor/CMakeLists.*.txt` 和 `patches/`。
- **Android（bionic）相容補丁**：[`patches/`](patches/) 目錄，改編自 [Termux 的 android-tools 套件](https://github.com/termux/termux-packages/tree/master/packages/android-tools)，
  例如讓 API 24 也能編譯、日誌輸出到 stderr 而不是 logcat、支援 termux-exec 和 `TERMUX_USB_FD`、Android 上沒有 `/tmp` 時改用 `/data/local/tmp`。

### 新版 Android 出來時編譯失敗怎麼辦

AOSP 大版本更新（例如 Android 18）後，第一次自動編譯可能會因為補丁對不上而失敗，Actions 會寄失敗通知。
通常 nmeum/android-tools 會在幾週內跟進，之後每天的排程會自動重試並成功。
如果是 [`patches/`](patches/) 裡的補丁對不上，需要依新版原始碼更新補丁。

## 在電腦上自己編譯

需要 Linux x86_64，以及 `git curl cmake ninja patch unzip zip` 和主機的 C/C++ 編譯器：

```sh
scripts/build.sh                    # 最新的 AOSP 標籤
scripts/build.sh android-17.0.0_r1  # 指定標籤
```

結果在 `dist/`。設定了 `ANDROID_NDK_HOME` 會直接使用該 NDK，否則自動下載。

## 授權

adb 及其他 AOSP 元件為 Apache License 2.0；boringssl、protobuf、brotli、lz4、zstd、fmtlib、libusb 各有自己的授權，
全文都附在 Release 的 `adb-arm64-v8a.zip` 裡的 `licenses/` 目錄。
