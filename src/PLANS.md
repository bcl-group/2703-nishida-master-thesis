# PLANS.md

## タスク概要
`two_rink_reaching_jerk_change.ipynb` を用いて、
2リンクアームの到達運動シミュレーションを実行し、
手先軌道の直線性とベル型速度プロファイルを改善するための
パラメータ調整を行う。

ただし今後は、1回ごとに notebook を直接書き換えて回すのではなく、
**3候補の config JSON を作成し、ユーザーがまとめて実行し、Codex が横比較して次候補を出す**
という batch 方式を採用する。

---

## 現在の方針
- notebook は `current_run_config.json` を読む
- candidate ごとの設定は `configs/<batch_id>/candidate_*.json` に置く
- ユーザーが `run_batch.sh` で 3候補をまとめて実行する
- 各 candidate の結果は `runs/<batch_id>/<candidate_id>/` に保存する
- batch 全体の比較表・比較図・分析文は `batch_results/<batch_id>/` に保存する
- 結果が全部そろった後に、Codex が横比較と次候補提案を行う

---

## 実行単位
### 1 batch
- candidate_01
- candidate_02
- candidate_03

の3候補を基本単位とする。

### 1 candidate
1つの candidate は、
- 1〜2個のパラメータ変更
- 明確な変更意図
を持つ。

---

## ディレクトリ構成
- `configs/<batch_id>/candidate_01.json`
- `configs/<batch_id>/candidate_02.json`
- `configs/<batch_id>/candidate_03.json`

- `runs/<batch_id>/candidate_01/`
- `runs/<batch_id>/candidate_02/`
- `runs/<batch_id>/candidate_03/`

- `batch_results/<batch_id>/summary.csv`
- `batch_results/<batch_id>/summary.md`
- `batch_results/<batch_id>/<batch_id>_plots.pdf`
- `batch_results/<batch_id>/*.png`
- `batch_results/<batch_id>/analysis.md`
- `batch_results/<batch_id>/batch_manifest.json`

- `codex_tuning_history.md`

---

## 変更対象候補
以下のパラメータを変更対象候補とする。

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

---

## 定量評価方法

### 1. 成功率
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
- 1 に近いほど良い

### 4. 報酬
- `mean_total_reward_1000`
- `mean_total_reward_100`
- `last_eval_mean_reward`

### 5. 補助
- `last_eval_mean_ep_length`

---

## 変更戦略

### 基本ルール
- 1候補で変更は最大2パラメータまで
- 原則として変更幅は ±20% 以内
- 3候補は、異なる仮説比較か、同一仮説の軽・中・強調整にする

### 優先的に調整する候補
#### A. ベル型速度プロファイル改善
- `REWARD_P_V_TER`
- `REWARD_P_V_POS`
- `REWARD_P_ACC`
- `REWARD_J`
- `JERK_RAMP_INIT_FACTOR`
- `JERK_RAMP_EPISODES`

#### B. 直線性改善
- `SHAPING_DIST_COEFF`
- `STEPS_MAX`
- `TRUNCATION_PENALTY`

#### C. 時間的ばらつき・終端条件調整
- `SIGMA_T`
- `R_GOAL`

#### D. 学習安定性調整
- `LEARNING_RATE`
- `BATCH_SIZE`
- `HID_LAY`

---

## 推奨変更の考え方
### ケース1
成功率は高いが、速度ピークが早すぎる / 多峰性がある
- `REWARD_P_ACC`
- `REWARD_J`
- `REWARD_P_V_POS`
- `JERK_RAMP_*`

### ケース2
成功率は高いが、軌道が曲がる
- `SHAPING_DIST_COEFF`
- `STEPS_MAX`
- `TRUNCATION_PENALTY`

### ケース3
成功率が不安定
- `LEARNING_RATE`
- `BATCH_SIZE`
- `R_GOAL`
- `SIGMA_T`

### ケース4
post-moving で不自然な補正が出る
- `REWARD_P_V_POS`
- `REWARD_P_ACC`
- `POST_MOVING_TIME`

---

## batch 実行手順

### Step 1
Codex が `configs/<batch_id>/candidate_01.json` 〜 `candidate_03.json` を作る

### Step 2
ユーザーが `run_batch.sh` でその batch を実行する

### Step 3
各 candidate について以下を確認する
- `runs/<batch_id>/<candidate_id>/run_manifest.json`
- `runs/<batch_id>/<candidate_id>/codex_iteration_summary.json`

### Step 4
batch 全体について以下を確認する
- `batch_results/<batch_id>/summary.csv`
- `batch_results/<batch_id>/summary.md`
- `batch_results/<batch_id>/*.png`
- `batch_results/<batch_id>/<batch_id>_plots.pdf`

### Step 5
結果が3候補分そろったら、Codex が比較分析を行う

### Step 6
Codex は以下を書き出す
- `batch_results/<batch_id>/analysis.md`
- `codex_tuning_history.md`

### Step 7
Codex は今回の分析結果を踏まえて次 batch の候補 JSON を作る

---

## 採用判断
- 成功率が最も重要
- 成功率が同等なら `peak_count`、`peak_time_ratio`、`gauss_center_error`、`gauss_rmse`、`gauss_r2`
- その次に `path_length_ratio`
- 最後に報酬
- 必要なら「どれも採用しない」を選んでよい

---

## 停止条件
- 1 batch ごとに結果を確認する
- 3 batch 連続で主要指標が改善しない場合は停止候補
- 成功率が著しく悪化する場合は、その方向の仮説を打ち切る
- 自動化失敗は、科学的失敗と分離して扱う

---

## 各 batch の記録テンプレート

## Batch <batch_id>
- 実行日時:
- candidate_01 の変更:
- candidate_02 の変更:
- candidate_03 の変更:
- candidate_01 の結果:
- candidate_02 の結果:
- candidate_03 の結果:
- 採用候補:
- 採用理由:
- 不採用理由:
- 次 batch の方針:

---

## 現在の最重要方針
- notebook 本体は極力固定する
- パラメータ変更は config JSON に閉じ込める
- 実行と分析を分離する
- 結果が全部そろった後にのみ Codex で比較する
- candidate ごとの結果対応付けを厳密に保つ
- 実行は常にユーザーが担当する
- Codex は比較分析・履歴記録・次候補作成に集中する