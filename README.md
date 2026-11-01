# my-airi

AIRI とローカルの LLM・音声合成サーバーをまとめて利用するための Nix flake です。
対象は `x86_64-linux` です。

| 用途 | 利用するソフトウェア |
| --- | --- |
| AI キャラクターのデスクトップアプリ | AIRI |
| LLM | CLIProxyAPI（Codex の OAuth 認証を使う OpenAI API 互換サーバー） |
| 音声合成（TTS） | AivisSpeech Engine（CPU 動作） |
| 音声認識（ASR） | 未設定 |

## 導入方法

以下の単体起動の手順を利用します。
Codex の初回認証と AIRI 内のプロバイダー設定は必要です。
CLIProxyAPI は非公式の互換サーバーです。利用権限のあるアカウントで、提供元の規約に従って利用してください。
サーバーをインターネットに公開しないでください。

## 単体で起動する

このリポジトリの `flake.nix` があるディレクトリで作業します。
Nix の flakes が有効になっている必要があります。
初回実行時にキャッシュ設定の許可を求められた場合は、表示される URL と公開鍵を確認して許可してください。

### 1. 設定用ディレクトリと API キーを用意する

```sh
mkdir -p ~/.config/my-airi ~/.local/share/my-airi/cli-proxy-auth
chmod 700 ~/.config/my-airi ~/.local/share/my-airi/cli-proxy-auth
```

CLIProxyAPI に接続するためのランダムな秘密鍵を用意します。
OpenSSL が利用できる場合は、次のコマンドで生成できます。
既存の鍵がある場合は、そのまま利用してください。次の例は上書きを拒否します。

```sh
(
  umask 077
  set -o noclobber
  openssl rand -hex 32 > ~/.config/my-airi/proxy-api-key
)
```

この鍵は **ローカルプロキシ用**です。OpenAI の API キーや Codex の OAuth トークンではありません。
鍵や認証情報を Git にコミットしないでください。

### 2. CLIProxyAPI の設定ファイルを作成する

`~/.config/my-airi/cli-proxy-api.yaml` に以下を記述します。
`ここを生成した秘密鍵に置き換える` の部分には、先ほどの `proxy-api-key` ファイルの内容を設定してください。

```yaml
config-version: 8
server:
  host: "127.0.0.1"
  port: 8317
management:
  secret-key: ""
  disable-control-panel: true
access:
  api-keys:
    - "ここを生成した秘密鍵に置き換える"
oauth:
  auth-dir: "~/.local/share/my-airi/cli-proxy-auth"
observability:
  logs:
    logging-to-file: false
```

```sh
chmod 600 ~/.config/my-airi/cli-proxy-api.yaml
```

### 3. Codex にログインする

```sh
nix run .#login
```

表示される案内に従って、ブラウザで認証してください。
通常は初回のみ必要で、再認証を求められた場合にもう一度実行します。

### 4. 三つを同時起動する

```sh
nix run .#start
```

`nix run .` でも同じ動作になります。初回は AIRI のビルドに時間がかかる場合があります。
AivisSpeech Engine の初回起動時は、音声モデルと BERT モデルが自動取得されます。
インターネット接続と、モデル用に約 1 GB の空き容量が必要です。

起動元の端末は開いたままにしてください。
明示的に停止する場合は、起動元の端末で `Ctrl+C` を押してください。

別の設定ファイルを使う場合は、ログイン時と起動時の両方に `MY_AIRI_PROXY_CONFIG` を指定します。

```sh
MY_AIRI_PROXY_CONFIG=/絶対パス/cli-proxy-api.yaml nix run .#login
MY_AIRI_PROXY_CONFIG=/絶対パス/cli-proxy-api.yaml nix run .#start
```

### コマンドをインストールする

```sh
nix profile install .
```

インストール後は、次のコマンドを利用できます。

```sh
airi-codex-login
start-airi
```

## AIRI 内の接続設定

この設定は AIRI の画面内で行います。

### LLM：Codex を利用する

プロバイダー設定で **OpenAI Compatible** を追加し、以下を指定します。

| 項目 | 設定値 |
| --- | --- |
| API 方式 | Chat Completions |
| Base URL | `http://127.0.0.1:8317/v1` |
| API キー | ローカルプロキシ用に用意した秘密鍵 |
| モデル | 一覧を取得して、利用可能な GPT／Codex モデルを選択 |

保存後、会話用のモデル設定でも、追加したプロバイダーとモデルを選択します。
AIRI に Codex の OAuth トークンを入力する必要はありません。認証は CLIProxyAPI が担当します。

### TTS：AivisSpeech を利用する

音声合成のプロバイダーに **AivisSpeech** を選択します。

| 項目 | 設定値 |
| --- | --- |
| Base URL | `http://127.0.0.1:10101` |
| 音声 | 一覧からインストール済みの話者・スタイルを選択 |

音声合成の設定でも、そのプロバイダーと音声を選択してください。
まずはテキストで話しかけ、LLM の返答と読み上げができるか確認します。
ASR は未設定のため、マイク入力の設定は別途必要です。

## 起動に失敗した場合

ログは `${XDG_STATE_HOME:-$HOME/.local/state}/my-airi/` に出力されます。

```sh
tail -n 50 ~/.local/state/my-airi/cli-proxy-api.log
tail -n 50 ~/.local/state/my-airi/aivisspeech-engine.log
```

ログを他人に共有する場合は、鍵・トークン・アカウント情報を除去してください。

### `A backend stopped unexpectedly`／`address already in use`

既に別の `start-airi` が動いていないか確認してください。

```sh
ss -ltnp '( sport = :8317 or sport = :10101 )'
```

以前の AIRI が起動済みなら、その画面を利用できます。
再起動したい場合は、以前の起動元の端末で `Ctrl+C` を押してから起動し直してください。

### 初回起動に時間がかかる

AivisSpeech の初回モデル取得には数分かかる場合があります。
インターネット接続と空き容量を確認し、ログを見ながらお待ちください。
