---
name: my-voice
description: GitHub の Issue・PR・コメント・レビューコメントの本文を、本人（striderkein）の文体と判断の軸で書く、または書き直す。「Issue 起票して」「PR 本文を書いて」「コメント返して」「私っぽく書いて」「自分の文体で」「文体を整えて」等で発動。他の起票スキル（create-pr、create-bug-issue など）が本文を組み立てる段階でも使う。
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# my-voice

Issue・PR・コメントの本文を、striderkein が自分で書いたと読める文にする。

骨格は「読み手に親切な整えた文」、判断の軸と一言の本音は「素の声」から取る。どちらも本人の実際の発言から抜き出したもので、出典の種類は [references/style.md](references/style.md) の冒頭にある。

## 使う資料

| ファイル | 中身 | いつ読むか |
|---|---|---|
| [references/values.md](references/values.md) | 判断の軸。何を書くか・書かないかを決める | 毎回、書く前に |
| [references/style.md](references/style.md) | 骨格・文・語彙・本音の入れ方 | 毎回 |
| [references/examples.md](references/examples.md) | 書き直し前と後の対 | 迷ったとき |
| `scripts/lint-voice.sh` | AI 臭い定型句と書式の機械検査 | 書き終えたら必ず |

## 手順

### 1. 事実をそろえる

本文に書く事実は、この会話で調べたものだけにする。ファイル・行番号・件数・run の URL・確かめた日付を手元に集める。足りない事実は推測で埋めず、本文で「まだ確かめていない」と書く。

### 2. 判断の軸に当てる

[references/values.md](references/values.md) を読み、書く前に次を自問する。答えが本文の Why と提案に出る。

- 測った数字があるか。無ければ、測る手段を書けるか
- 根本の原因に届いているか。届かないなら、段階を切った理由を書けるか
- 人の手間を増やしていないか。標準機能や既存の仕組みで足りないか
- 消せるものを残していないか
- 仕組みで防げるものを、人の注意に頼っていないか

### 3. 骨格を選ぶ

[references/style.md](references/style.md) の「骨格」から選ぶ。リポジトリに Issue / PR テンプレートがある場合はそちらが優先で、見出しの中身をこのスキルの文体で書く。

### 4. 書く

[references/style.md](references/style.md) の「文」「語彙」に沿って書く。一言の本音は「本音の入れ方」の条件を満たすときだけ、本文に 1 つまで入れる。

### 5. 機械検査

本文をファイル（ここでは `draft.md`）に書き出し、検査する。

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/lint-voice.sh" draft.md
```

ERROR は直す。WARN は理由があれば残してよい。

### 6. 読み直し

投稿前に、次の 3 点だけ読み直す。

- タイトルだけ読んで、何がどうなる話か分かるか
- Why を消したら、この Issue を起こす理由が消えるか（消えないなら Why が空回りしている）
- 本人が読んで「こんなこと言わない」と思う一文が無いか。特に、なだめ・前置き・締めの挨拶

## 育て方

- 出した Issue や PR に「自分ならこう書かない」があったら、その前と後を [references/examples.md](references/examples.md) に足す
- 同じ直しが 2 回出たら、[references/style.md](references/style.md) の規則にするか、`lint-voice.sh` の検査にする
- 規則を変えたら `bash scripts/tests/test-lint.sh` を通す
- 規則の根拠を集め直すときは `tools/collect-corpus.sh` を使う。出力先の `corpus/` は gitignore 済み

## 会社の情報を入れない

このスキルは所属が変わっても持ち歩く。会社の業務の中身（顧客名・案件名・社内 URL・アカウント ID・社内の数値）は置かない。`corpus/` の本文はコミットせず、規則と、固有名と数値を差し替えた例文だけを置く。
