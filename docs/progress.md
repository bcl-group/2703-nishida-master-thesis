# **5/21~5/27にしたこと**  
## したこと  
1. リファクタリング
2. 躍度の報酬に対するカリキュラム学習の実装
- 15000 episode経過時にスタート
- 100 episodeごとのゴール到達率の平均を計算（ゴール到達は運動終了時に手先の終端が目標地点の 3 cm 以下にあること）
- 80 % 以上で今の躍度の重み✖️1.2
- 50 % 以下で今の躍度の重み✖️0.8
- 終了条件：躍度の重みに閾値を与え、それを満たしつつ、その報酬を含めた全体の報酬の閾値を満たしたら終了

## 困っていること
- 学習の進みが遅い
- インターバルなしで評価フェーズを繰り返すのはどうなのか
- 3 cm は少し厳しいかもしれない⇨結構失敗する

## 今後のtodo  
- GPUを用いた実装
- 更なる改良

# **5/13~5/20にしたこと**  
## したこと  
1. 論文を読んでいる
- Optimal control of reaching includes kinematic constraints
- Michael Mistry, Evangelos Theodorou, Stefan Schaal, and Mitsuo Kawato
- https://journals.physiology.org/doi/full/10.1152/jn.00794.2011
- 内容：リーチング中に加速度に依存する一時的な外乱を加えた際に、ヒトはどのような運動戦略でそれに適応するのか

## 困っていること
特になし  

## 今後のtodo  
- 研究を進める
- 論文を読み切る


# **4/15~4/22にしたこと**  
## したこと  
1. 論文を読んだ
- Reinforcement learning control of a biomechanical model of the upper extremity
- Florian Fischer, Miroslav Bachinski, Markus Klar, Arthur Fleig & Jörg Müller
- https://www.nature.com/articles/s41598-021-93760-1
- 内容：3次元においての上肢の完璧な骨格モデルでもフィッツの法則（目標が遠いほど時間がかかる、目標が小さいほど時間がかかる）と2/3累乗法則（曲がった軌道を描くとき、速度と曲率（曲がり具合）との関係）の両方が、信号に依存して定常的に発生するノイズの下で、移動時間を最小化するという直接的な結果を得るために見られることを確認する

## 困っていること
特になし  

## 今後のtodo  
- 研究を進める
