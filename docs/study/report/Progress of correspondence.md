# PPOの処理順と、維持・除去・置換の現状

更新日：2026-10-16（Asia/Tokyo）。今回は数式や新しい回路の導出を進めず、PPOの流れと各処理の扱いを整理する。実装変更・本学習は行っていない。

ユーザーの最新指定：図は使わず、Notionへ貼ることを想定した通常のMarkdownとLaTeX数式にする。全文をコードブロックに入れる形式は、数式が文字列になったため撤回。説明の対象は「強化学習は理解しているがPPOを知らない人」。日本語で分かりにくくなる箇所は数式を使い、sigmaの生成元、terminated/truncatedの意味、保存するlog確率密度、Adamの更新対象を具体的に書く。指導教員との合意に関する注記と、使っていないエントロピー項は提示内容から省く。

ここで扱うPPO（clip版）は、収集時の方策で得た軌道データを固定し、同じデータから方策と価値関数を複数回更新するActor–Critic法。Actorでは収集時との方策比を使い、クリッピングでサンプルの勾配寄与を制限する。

## 今回追加された実験結果

別PCでの実験についてのユーザー報告。ローカルのログを再解析した結果ではない。

- Actorのsigmaを固定した条件は、複数シードでうまくいかなかった。ただし、到達できていた試行もあった。
- `BATCH_SIZE=1`、すなわち経験1件ずつ勾配更新する条件も、複数シードでうまくいかなかった。
- 「バッチ数1」の意味は、ユーザーの最終訂正により`BATCH_SIZE=1`と確認した。「収集データ全体を1バッチで更新」「N_STEPS=1」「N_EPOCHS=1」とは扱わない。
- sigmaを報酬に基づいて動的に調整すれば、ある程度うまくいくのではないか、というユーザーの見通しがある。これは次の置換候補であり、成功確認済みではない。
- sigmaの固定値、試したseed数・値、他のハイパーパラメータ、評価指標・成績は未確認。

## 判定の意味

- **除去不可（現時点）**：今回の変更実験では学習がうまくいかなかったため、現在は残す判断。
- **置換可能（確認済み）**：別の処理へ置き換えて学習できたというユーザー報告がある。生理学的対応の確定とは区別する。
- **置換候補（未検証）**：置換案はあるが、学習が成立するかは未確認。
- **未検証**：除去・置換の成否を判断する結果がまだ共有されていない。
- **維持**：現在のモデルで引き続き使用する。

## Notion用：上から順に見る処理と判定

**PPO＋Running RMS：処理順と除去・置換の状況**

「除去不可（現時点）」は、今回の実験結果に基づいて現在は残すという判断を表す。

**使用するパラメータ**

| 記号 | 内容 |
| --- | --- |
| $\theta_\mu$ | Actorの隠れ層・平均出力層の重みとバイアス |
| $\ell$ | Actorが保持する、行動の各次元の学習可能な`log_std` |
| $\sigma=\exp(\ell)$ | 行動の各次元の標準偏差。指数関数は成分ごとに適用 |
| $\theta=(\theta_\mu,\ell)$ | Actor全体のパラメータ |
| $\phi$ | Criticの隠れ層・価値出力層の重みとバイアス |

現行実装では、平均$\mu$は状態から計算し、$\ell$はネットワーク出力とは別のパラメータとして保持する。$\sigma$は状態に直接依存しないが、学習によって変化する。

**1. Actor・Criticの出力を計算｜維持**

状態$s_t$を入力し、行動分布の平均と状態価値を求める。

$$
\mu_{\mathrm{old}}(s_t),\qquad V_{\mathrm{old}}(s_t)
$$

oldは「今回のRolloutの収集に使うモデル」を表す。収集中はActor・Criticのパラメータを更新しない。

**2. 方策分布を構成し、行動をサンプリング｜σの調整は除去不可（現時点）／更新則は置換候補（未検証）**

保持している$\ell_{\mathrm{old}}$から標準偏差を求め、ガウス方策を構成する。

$$
\sigma_{\mathrm{old}}=\exp(\ell_{\mathrm{old}})
$$

$$
\pi_{\mathrm{old}}(\cdot\mid s_t)
=\mathcal{N}\!\left(\mu_{\mathrm{old}}(s_t),\operatorname{diag}(\sigma_{\mathrm{old}}^2)\right)
$$

$$
\epsilon_t\sim\mathcal{N}(0,I),\qquad
a_t=\mu_{\mathrm{old}}(s_t)+\sigma_{\mathrm{old}}\odot\epsilon_t
$$

$\odot$は成分ごとの積。固定σ条件は複数seedでうまくいかなかったが、到達できた試行もある。報酬に基づくσの調整は置換候補であり、未検証。

**3. 環境を1ステップ進める｜維持**

行動を環境の入力範囲に制限して渡し、報酬$r_t$、次状態$s_{t+1}$、`terminated`、`truncated`を取得する。

- `terminated`：課題そのものの終了条件を満たしたこと。現環境では到達後の評価区間終了など。
- `truncated`：最大ステップ数などの制限により打ち切ったこと。

真の終端では、その先の状態価値による補完を行わない。時間制限による打ち切りでは、打ち切られた時点の状態価値を使って補完する。リセット後の初期状態の価値とは区別する。

**4. Rolloutを収集・保存する｜収集方法の変更は未検証**

1〜3を`N_STEPS`分繰り返す。Rolloutは1エピソードと一致する必要はなく、エピソードをまたぐことも、途中で収集を区切ることもある。

状態・行動・報酬・エピソード境界に加え、次を保存する。

$$
\mathrm{logp}^{\mathrm{old}}_t=\log\pi_{\mathrm{old}}(a_t\mid s_t),\qquad
v^{\mathrm{old}}_t=V_{\mathrm{old}}(s_t)
$$

$\log\pi_{\mathrm{old}}(a_t\mid s_t)$は、収集した状態・行動に対するlog確率密度。ここではこれらの値を保存すればよく、旧ネットワーク全体を別に保持する必要はない。方策比には、環境の入力範囲に制限する前のサンプル$a_t$を使う。

**5. GAEでAdvantageを計算｜除去・置換は未検証**

報酬列と収集時の価値予測から、調整前のAdvantage $A_t^{\mathrm{raw}}$を一度計算する。

今回の収集データを学習している間は固定する。Criticが更新されても、同じRolloutの$A_t^{\mathrm{raw}}$を計算し直さない。

**6. Criticの学習目標を作る｜構成・固定手順の置換は未検証**

$$
Y_t=v^{\mathrm{old}}_t+A_t^{\mathrm{raw}}
$$

今回の学習中は$Y_t$を固定し、目標側へ勾配を流さない。

**7. Actor用Advantageをスケーリング｜置換可能（確認済み）**

$$
A_t^{\mathrm{used}}=\frac{A_t^{\mathrm{raw}}}{\mathrm{RMS}_{\mathrm{past}}+\varepsilon_{\mathrm{RMS}}}
$$

バッチ内標準化から、過去のRolloutに基づくRunning RMSへ置換済み。正の値で割るため、Advantageの符号を保つ。

$\mathrm{RMS}_{\mathrm{past}}$と$A_t^{\mathrm{used}}$は今回の全epochで固定する。Criticの目標$Y_t$には、スケーリング前の$A_t^{\mathrm{raw}}$を使う。

**8. ミニバッチを構成｜勾配集約は除去不可（現時点）**

収集データをシャッフルし、`BATCH_SIZE`件ずつ取り出す。各サンプルの損失を平均し、その勾配を使って更新する。

`BATCH_SIZE=1`条件は複数seedでうまくいかなかった。ただし、バッチサイズの変更に伴ってoptimizerの更新回数も変わるため、失敗の原因を勾配平均の有無だけに限定しない。シャッフル自体の必要性は未検証。

**9. 現在のActor・Criticで再評価｜維持**

保存した同じ$s_t$と$a_t$について、現在のパラメータで次を計算する。

$$
\mathrm{logp}_t=\log\pi_\theta(a_t\mid s_t),\qquad
v_t=V_\phi(s_t)
$$

行動の再サンプリングや、環境からの報酬の再取得は行わない。

**10. 方策比を計算｜除去・置換は未検証**

$$
\rho_t(\theta)
=\exp\!\left(\mathrm{logp}_t-\mathrm{logp}^{\mathrm{old}}_t\right)
=\frac{\pi_\theta(a_t\mid s_t)}{\pi_{\mathrm{old}}(a_t\mid s_t)}
$$

分母に相当する収集時のlog確率密度は固定し、現在のlog確率密度を計算し直す。保存した行動が、収集時と比べてどれだけ出やすくなったかを表す。

**11. Actorの損失を計算｜除去・置換は未検証**

ミニバッチを$B$、`CLIP_RANGE`を$c$とする。

$$
L_A(\theta)
=-\frac{1}{|B|}\sum_{t\in B}
\min\!\left[
\rho_t(\theta)A_t^{\mathrm{used}},\;
\operatorname{clip}\!\left(\rho_t(\theta),1-c,1+c\right)A_t^{\mathrm{used}}
\right]
$$

Advantageの符号と方策比に応じて、そのサンプルの勾配寄与を制限する。方策の変化量全体を必ず一定範囲内に収める処理ではない。

**12. Criticの損失を計算｜維持**

$$
L_V(\phi)=\frac{1}{|B|}\sum_{t\in B}\left(V_\phi(s_t)-Y_t\right)^2
$$

固定した$Y_t$へ、現在の価値予測$V_\phi(s_t)$を近づける。現在の設定では価値関数クリッピングは使わない。

**13. 誤差逆伝播で勾配を計算｜維持**

$$
L=L_A+c_VL_V,\qquad c_V=\texttt{VF\_COEF}
$$

- Actorの$\theta_\mu$と$\ell$には、Actor損失から勾配が流れる。
- Criticの$\phi$には、重み付けしたCritic損失から勾配が流れる。
- 保存値$\mathrm{logp}^{\mathrm{old}}_t$、$A_t^{\mathrm{used}}$、$Y_t$には勾配を流さない。

**14. 勾配ノルムを制限｜分離への置換可能（確認済み）**

Actor側（$\theta_\mu,\ell$）とCritic側（$\phi$）の勾配ノルムを、それぞれ別に制限する。

Actor・Criticをまとめて制限する方式から、別々に制限する方式への置換は確認済み。制限自体を完全に除去できるかは未検証。

**15. Adamでパラメータを更新｜Adamは維持／σ更新則は置換候補（未検証）**

共通optimizerの1回の`step()`で、次を更新する。

| 更新対象 | 更新されるもの |
| --- | --- |
| $\theta_\mu$ | Actorの隠れ層・平均出力層の重みとバイアス |
| $\ell$ | 行動の各次元の`log_std` |
| $\phi$ | Criticの隠れ層・価値出力層の重みとバイアス |

更新後の$\ell$から標準偏差を求める。

$$
\sigma_{\mathrm{new}}=\exp(\ell_{\mathrm{new}})
$$

したがって、Actorでは平均$\mu$と標準偏差$\sigma$の両方が変わり得る。Criticの価値予測と、両ネットワークの中間層の活動も変わり得る。

現在のσはActor損失の勾配によって学習する。報酬に基づく別の調整則への置換は、今後の検証対象。

**16. 同じデータをN_EPOCHS周学習｜再利用の除去・回数変更は未検証**

収集データ全体を一巡することを1epochとし、8〜15を繰り返す。ActorとCriticの周回数は共通。

| 今回のRolloutの学習中に固定するもの | 更新・再計算するもの |
| --- | --- |
| 保存した状態・行動・報酬、$\mathrm{logp}^{\mathrm{old}}_t$、$v^{\mathrm{old}}_t$、$A_t^{\mathrm{raw}}$、$A_t^{\mathrm{used}}$、$Y_t$ | 現在のパラメータ、$\mu$、$\sigma$、$\mathrm{logp}_t$、$V_\phi(s_t)$、方策比、損失、勾配 |

ActorとCriticは各ミニバッチで一緒に更新される。Actorの全epochを終えてからCriticの全epochを始める順序ではない。

**17. 履歴を更新し、次のRolloutへ｜維持**

現在の$A_t^{\mathrm{raw}}$をRunning RMSの履歴へ一度反映する。その後、更新後のActor・Criticで次のRolloutを収集する。

次のRolloutでは、$\mathrm{logp}^{\mathrm{old}}_t$、$v^{\mathrm{old}}_t$、$A_t^{\mathrm{raw}}$、$Y_t$を新たに作る。oldの基準はRolloutごとに更新される。

処理順の根拠：[SB3収集処理](https://stable-baselines3.readthedocs.io/en/v2.9.0/_modules/stable_baselines3/common/on_policy_algorithm.html)、[RolloutBuffer](https://github.com/DLR-RM/stable-baselines3/blob/v2.9.0/stable_baselines3/common/buffers.py)、[PPO学習処理](https://stable-baselines3.readthedocs.io/en/v2.9.0/_modules/stable_baselines3/ppo/ppo.html)、ローカル`running_rms_ppo_tmux/running_rms_ppo.py`。

## 今回の結果から断定しないこと

- 固定sigmaで到達例があるため、「固定sigmaでは到達そのものが不可能」としない。報酬でsigmaを調整する方式の成功もまだ断定しない。
- `BATCH_SIZE=1`が失敗しても、「脳でも複数経験を同時に保存して平均しなければ学習不能」としない。まず試したソフトウェア条件での結果として扱う。
- `BATCH_SIZE`を変えると、1更新当たりの平均化の有無だけでなく、同じ収集データ・同じN_EPOCHSに対するoptimizer stepの回数も変わる。学習率等の詳細未確認のまま、原因を一つに固定しない。
- `N_STEPS`、`BATCH_SIZE`、`N_EPOCHS`は別の処理を制御する。今回確認したのは`BATCH_SIZE=1`条件の結果。
- ユーザーの指定に従い、実験で失敗した変更は「除去不可（現時点）」と表記する。今回の条件で維持する判断と、あらゆる設定で永久に除去不可能という主張は区別する。
