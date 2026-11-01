# my-airi

AIRI とローカルの LLM・音声合成サーバーをまとめて利用するための Nix flake です。
対象は `x86_64-linux` です。

| 用途 | 利用するソフトウェア |
| --- | --- |
| AI キャラクターのデスクトップアプリ | AIRI |
| LLM | CLIProxyAPI（Codex の OAuth 認証を使う OpenAI API 互換サーバー） |
| 音声合成（TTS） | AivisSpeech Engine（CPU 動作） |
| 音声認識（ASR） | 未設定 |

AIRI は upstream の `main` を flake input として取り込み、取得した版を
`flake.lock` で管理します。Nix の修正を含む [PR #3290](https://github.com/moeru-ai/airi/pull/3290)
は取り込み済みです。

## 導入方法

以下の単体起動の手順を利用します。
Codex の初回認証と AIRI 内のプロバイダー設定は必要です。
CLIProxyAPI は非公式の互換サーバーです。利用権限のあるアカウントで、提供元の規約に従って利用してください。
サーバーをインターネットに公開しないでください。

## 単体で起動する

このリポジトリの `flake.nix` があるディレクトリで作業します。
Nix の flakes が有効になっている必要があります。

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
認証情報は設定した `auth-dir` に保存され、Nix store には入りません。
通常は初回のみ必要で、再認証を求められた場合にもう一度実行します。

### 4. 三つを同時起動する

```sh
nix run .#start
```

`nix run .` でも同じ動作になります。初回は AIRI のビルドに時間がかかる場合があります。
CLIProxyAPI と AivisSpeech Engine の応答を待ってから AIRI を起動します。
AivisSpeech Engine の初回起動時は、音声モデルと BERT モデルが自動取得されます。
インターネット接続と、モデル用に約 1 GB の空き容量が必要です。

起動元の端末は開いたままにしてください。AIRI のプロセスが終了すると、起動した二つのサーバーも停止します。
明示的に停止する場合は、起動元の端末で `Ctrl+C` を押してください。

別の設定ファイルを使う場合は、ログイン時と起動時の両方に `MY_AIRI_PROXY_CONFIG` を指定します。

```sh
MY_AIRI_PROXY_CONFIG=/絶対パス/cli-proxy-api.yaml nix run .#login
MY_AIRI_PROXY_CONFIG=/絶対パス/cli-proxy-api.yaml nix run .#start
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
現在のランチャーは既存サーバーを再利用せず、二重起動するとポート競合で失敗します。
起動確認が既存サーバーの応答を拾う場合もあるため、URL が表示されても新しいサーバーが起動成功したとは限りません。

### 初回起動に時間がかかる

AivisSpeech の初回モデル取得には数分かかる場合があります。
ランチャーは各サーバーについて最大 900 回、応答を確認します。
バックエンドが終了すると、残りのプロセスも停止します。
CLIProxyAPI の HTTP 401 は接続待ち受けの確認に使いますが、Codex の認証成功を保証するものではありません。

## パッケージのビルドと更新

### バイナリキャッシュ

この flake は次のキャッシュ URL と署名検証用の公開鍵を `nixConfig` に設定しています。

| 対象 | キャッシュ |
| --- | --- |
| nixpkgs のパッケージ | `https://cache.nixos.org` |
| llm-agents のパッケージ（CLIProxyAPI） | `https://cache.numtide.com` |

初回実行時に flake のキャッシュ設定を許可するか尋ねられた場合は、URL と公開鍵を確認して許可してください。
コマンド単位で明示的に許可する場合は、次のように実行できます。

```sh
nix build --accept-flake-config .#cli-proxy-api
```

Nix デーモン側の信頼設定によっては、管理者によるキャッシュ URL・公開鍵の設定も必要です。
llm-agents 自身が固定している nixpkgs を維持し、配布済みキャッシュと同じパッケージ構成を利用します。
キャッシュに該当する成果物がない場合は通常のビルドになります。
AIRI 本体と独自の AivisSpeech derivation のビルド済み成果物まで、これらのキャッシュにあるとは限りません。

### ビルドと更新のコマンド

```sh
nix build .#airi
nix build .#aivisspeech-engine
nix build .#cli-proxy-api

# flake input を更新し、flake.lock に記録する
nix flake update
```

AivisSpeech Engine は [Release 1.2.0](https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0)
の Linux x64 向けビルド済みバイナリを取得する独自 derivation です。
この版は derivation 内で指定しているため、`nix flake update` だけでは更新されません。
版を更新する場合は取得 URL とハッシュも更新してください。
NVIDIA GPU の設定は含まず、CPU で動作します。配布アーカイブに含まれる GPU 用ライブラリも有効化しません。

## 検証

```sh
nix flake check
python3 -B -m unittest discover -s tests -v
```

flake の検証には、起動スクリプトの静的解析とライフサイクルテストが含まれます。
これらのテストでは Codex の実際の推論や AIRI の GUI 操作は行いません。
