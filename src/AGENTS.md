# AGENTS.md

## 目的
本リポジトリでは、`two_rink_reaching_jerk_change.ipynb` を用いて、
2リンクアームの到達運動シミュレーションを実行し、
手先軌道の直線性とベル型速度プロファイルの改善を目指して、
パラメータ調整を反復的に行う。

現在の運用では、notebook のパラメータセルを直接書き換えず、
`current_run_config.json` を介してパラメータを読み込み、
複数の候補 JSON を batch 単位で実行・比較する方式を用いる。

---

## 実行対象
- notebook: `two_rink_reaching_jerk_change.ipynb`
- active config: `current_run_config.json`
- candidate configs: `configs/<batch_id>/candidate_*.json`
- batch-run script: `run_batch.sh`
- evaluation script: `evaluate_latest_run.py`
- plotting script: `plot_batch_results.py`

---

## 役割分担
### Codex が行うこと
- 候補 JSON を作成・修正する
- batch 実行結果を横比較する
- `batch_results/<batch_id>/analysis.md` に全文の分析を書く
- `codex_tuning_history.md` に要約を追記する
- 次 batch の候補 JSON を作成する

### ユーザーが行うこと
- `./run_batch.sh configs/<batch_id>` をローカル shell で実行する
- batch 実行後に、必要に応じて再度 Codex を起動して分析を続行させる

### 明確な禁止事項
- Codex が `run_batch.sh` を自動実行しようとしないこと
- Codex から notebook を直接 `nbclient` / `jupyter nbconvert` / `execute_notebook.py` で起動しないこと
- notebook のパラメータセルを都度直接編集しないこと
- notebook 実行結果の対応付けを「最新3件」などの曖昧な方法で行わないこと

---

## 最重要方針
- notebook 本体は極力固定する
- パラメータ変更は config JSON に閉じ込める
- 候補ごとの結果対応付けは `batch_id` と `candidate_id` で厳密に管理する
- 「最新フォルダ依存」の運用を避ける
- 自動化失敗と科学的失敗を分離して扱う

---

## 実行前確認
以下を確認すること。

1. 仮想環境 Python が存在すること  
   `/Users/rikunishida114/Desktop/rl/SB/bin/python`
2. 次が通ること  
   `"/Users/rikunishida114/Desktop/rl/SB/bin/python" -c "import stable_baselines3, ipykernel, nbformat, nbclient, pandas, numpy, matplotlib; print('ok')"`
3. notebook は `current_run_config.json` を読む構造になっていること
4. `run_batch.sh` が実行可能であること
5. `configs/<batch_id>/candidate_*.json` が存在すること

---

## 設定ファイルの原則
### active config
- notebook は常に `current_run_config.json` を読む
- `run_batch.sh` が各 candidate JSON を実行前に `current_run_config.json` にコピーする

### candidate config の置き場所
- `configs/<batch_id>/candidate_01.json`
- `configs/<batch_id>/candidate_02.json`
- `configs/<batch_id>/candidate_03.json`

### batch_id
- `batch_id` は 1回の比較単位を表す
- 例: `batch_2026_05_15_01`
- `run_batch.sh` は受け取った `config_dir` のフォルダ名を `batch_id` とみなす

---

## 実行方法
### 基本
実行は常にユーザーがローカル shell から行うこと。

```bash
./run_batch.sh configs/<batch_id>
```
### Codex に関する原則
- Codex はまず `AGENTS.md` と `PLANS.md` を読むこと
- Codex は候補生成・比較分析・履歴記録・次候補作成を行うこと
- Codex は `run_batch.sh` を実行しないこと
- notebook 実行そのものは常にユーザーが担当すること

---

## 実行結果の保存先
### candidate ごとの結果
各候補の結果は以下に保存すること。

- `runs/<batch_id>/candidate_01/`
- `runs/<batch_id>/candidate_02/`
- `runs/<batch_id>/candidate_03/`

各 candidate ディレクトリには最低限以下を置くこと。
- `config_used.json`
- `run_manifest.json`
- `codex_iteration_summary.json`
- `logs_source` または対応する logs フォルダ参照
- notebook 実行エラー時は `executed.error.md`, `executed.error.json`

### batch ごとの結果
各 batch の比較結果は以下に保存すること。

- `batch_results/<batch_id>/summary.csv`
- `batch_results/<batch_id>/summary.md`
- `batch_results/<batch_id>/<batch_id>_plots.pdf`
- `batch_results/<batch_id>/*.png`
- `batch_results/<batch_id>/analysis.md`
- `batch_results/<batch_id>/batch_manifest.json`

### 履歴
- 全体履歴はリポジトリ直下の `codex_tuning_history.md` に保存する

---

## 変更可能範囲
### Codex が変更してよいもの
- `configs/<batch_id>/candidate_*.json`
- `batch_results/<batch_id>/analysis.md`
- `codex_tuning_history.md`

### 原則変更禁止
- notebook 本体の学習ロジック
- 環境クラス
- コールバック
- 可視化コード
- 学習コード本体
- `evaluate_latest_run.py`

### 自動化例外
純粋な自動化ブロッカーがある場合のみ、以下は修正してよい。
- `run_batch.sh`
- `plot_batch_results.py`
- `current_run_config.json` 読み込み部
- パス整理や manifest 出力

ただし、その場合は**科学的チューニングではなく自動化修正**であることを明記すること。

---

## 変更してよいパラメータ
候補 JSON で変更してよいパラメータは以下とする。

- `STEPS_MAX`
- `REWARD_P_V_TER`
- `REWARD_P_V_POS`
- `REWARD_P_ACC`
- `REWARD_J`
- `SIGMA_T`
- `R_GOAL`
- `SHAPING_DIST_COEFF`
- `TOTAL_TIMESTEPS`
- `LEARNING_RATE`
- `TAU`
- `HID_LAY`
- `BUFFER_SIZE`
- `BATCH_SIZE`
- `POST_MOVING_TIME`
- `DT`
- `JERK_RAMP_INIT_FACTOR`
- `JERK_SUCCESS_WINDOW_SIZE`
- `JERK_RAMP_SUCCESS_THRESHOLD`
- `JERK_RAMP_EPISODES`
- `REWARD_JE_LIM`
- `REWARD_LIMIT_HIT`
- `TRUNCATION_PENALTY`

それ以外の物理パラメータ・タスク定義は、明示的な指示がない限り固定とする。

---

## 変更ルール
- 1候補で変更してよいパラメータは **最大2個まで**
- 1回の変更幅は原則 **現在値の ±20% 以内**
- ただし以下は例外として固定刻み変更を許可する
  - `STEPS_MAX`: ±10 または ±20
  - `POST_MOVING_TIME`: ±2
  - `HID_LAY`: 64 ↔ 128 のような代表値変更可
  - `BATCH_SIZE`: 128, 256, 512 の代表値変更可
- 符号反転は禁止
- 各 candidate JSON に対して変更意図を明確にすること
- 3候補は、同じ仮説の微調整か、異なる仮説の比較かを明示すること

---

## 評価対象
評価は原則として **final model** に基づいて行う。

---

## 定量評価指標
### 1. 成功率
- 最優先指標
- `success_rate_1000`
- `success_rate_100`
- `success_rate_all`

### 2. ベル型速度プロファイル
- `peak_count`
- 理想は 1
- `peak_time_ratio`
- 理想値は 0.5
- `gauss_center_error`
- 理想は 0 に近い
- `gauss_rmse`
- 理想は 0 に近い
- `gauss_r2`
- 理想は 1 に近い

### 3. 直線性
- `path_length_ratio`

### 4. 報酬
- `mean_total_reward_1000`
- `mean_total_reward_100`
- `last_eval_mean_reward`

### 5. 評価時エピソード長
- `last_eval_mean_ep_length`

---

## 評価優先順位
1. 成功率
2. ベル型速度プロファイル
3. 直線性
4. 総報酬
5. 補助的に評価時エピソード長

---

## 採用判断
- 成功率が最も重要
- 成功率が同等なら `peak_count`、`peak_time_ratio`、`gauss_center_error`、`gauss_rmse`、`gauss_r2`
- その次に `path_length_ratio`
- 最後に報酬
- 必要なら「どれも採用しない」を選んでよい

---

## 記録ルール
### batch_results/<batch_id>/analysis.md
ここには以下を残すこと。
- 今回の3候補の比較
- ベスト候補
- ワースト候補
- 採用 / 不採用判断
- 今回の仮説が当たったかどうか
- 次に試す仮説
- 次 batch の候補方針

### codex_tuning_history.md
ここには以下を短く追記すること。
- batch_id
- 各 candidate の変更内容の要約
- 採用候補
- 不採用理由の要約
- 次の方針

---

## 停止条件
- 1 batch につき candidate は最大3個
- 3 batch 連続で主要指標が改善しなければ停止候補
- 成功率が著しく悪化する候補ばかりなら、基準設定に戻す
- 自動化失敗が続く場合は、まず shell / config / manifest の不整合を直す
- notebook 実行不能は科学的失敗ではなく、自動化失敗として分離して扱う

---

## 作業方針
- まず 3候補を作る
- ユーザーが `run_batch.sh` を実行する
- 結果がすべてそろった後にのみ Codex に比較分析をさせる
- Codex は notebook 実行そのものではなく、候補生成・比較分析・履歴記録・次候補作成に集中する
- 結果の対応付けは、必ず `batch_id` と `candidate_id` で行う
- 「最新フォルダ依存」の運用を避け、manifest と固定ディレクトリで管理する