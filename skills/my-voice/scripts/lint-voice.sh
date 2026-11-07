#!/usr/bin/env bash
# Issue / PR / コメントの下書きを my-voice の文体ルールで検査する。
# 使い方: lint-voice.sh <draft.md>
# 終了コード: 0 = ERROR なし / 1 = ERROR あり / 2 = 引数・ファイル不正
# コードフェンス（```）とインラインコードの中は検査しない。
set -u
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $(basename "$0") <draft.md>" >&2
  exit 2
fi

exec perl -CSD -Mutf8 -e '
use strict; use warnings;
my $file = shift;
open my $fh, "<:encoding(UTF-8)", $file or die "cannot open $file\n";
my @lines = <$fh>; chomp @lines;
my ($errors, $warns) = (0, 0);
sub err   { $errors++; print "ERROR L$_[0]: $_[1]\n" }
sub warn_ { $warns++;  print "WARN  L$_[0]: $_[1]\n" }

# AI が書いた印になる言い回し。本文に残っていたら直す。
my @error_rules = (
  [qr/以下[にで].{0,12}(まとめ|記載|説明|解説)(ます|します|いたします)/, "前置きの宣言は消して、いきなり本文を書く"],
  [qr/結論から(言う|申し上げる)と/, "「結論から言うと」は消して結論だけ書く"],
  [qr/参考になれば幸い/, "締めの定型句は消す"],
  [qr/ご確認のほど(よろしく|宜しく)お願い/, "締めの定型句は消す。頼むなら何を確かめてほしいかを書く"],
  [qr/(シームレス|堅牢|包括的|ベストプラクティス|多角的)/, "抽象語で押し切らず、何がどうなるかを書く"],
);
my @warn_rules = (
  [qr/本\s?(Issue|イシュー|PR|プルリクエスト|記事|ドキュメント)\s?(では|において)/, "「本イシューでは」はスコープの宣言（何をやり何をやらないか）なら残す。前置きなら消す"],
  [qr/(を|が)?(実施|実行)(しました|いたしました|致しました)/, "「実施しました」より「〜した」「〜を直した」"],
  [qr/(を)?行いました/, "「行いました」より具体的な動詞で"],
  [qr/一般的に|多くの場合|状況によって異なり|一概には言え/, "情報を増やさない安全クッション"],
  [qr/(最適化|効率化|向上)が(期待|見込ま)/, "期待を書かずに、測った数字か測る手段を書く"],
  [qr/(重要|効果的|最適)(です|である|な)/, "抽象語。何がどうなるかに置き換えられないか"],
  [qr/させていただ/, "「させていただく」は「します」で足りる"],
);

my ($in_fence, $bold, $emoji, $h2, $body_lines, $aside) = ("", 0, 0, 0, 0, 0);
my @tone = qw(ツライ つらい ガッチャンコ 知らんけど ええねん あれへん 要らない子 しっちゃかめっちゃか シッチャカメッチャカ 苦しゅうない よきにはからえ 捨て置け お主 ござる);
for my $i (0 .. $#lines) {
  my $n = $i + 1; my $raw = $lines[$i];
  # 閉じるのは、開いたときと同じ文字で同じ長さ以上の、それだけの行。4 連の中の 3 連では閉じない
  if (!$in_fence) {
    if ($raw =~ /^\s*(`{3,}|~{3,})/) { $in_fence = $1; next; }
  } else {
    my ($c, $len) = (substr($in_fence, 0, 1), length $in_fence);
    $in_fence = "" if $raw =~ /^\s*(\Q$c\E{$len,})\s*$/;
    next;
  }
  (my $l = $raw) =~ s/`[^`]*`//g;
  next if $l =~ /^\s*$/;
  next if $l =~ /^_?Generated (by|with)/ || $l =~ /claude-projects-attribution/;
  $body_lines++;
  for my $r (@error_rules) { err($n, $r->[1]) if $l =~ $r->[0]; }
  for my $r (@warn_rules)  { warn_($n, $r->[1]) if $l =~ $r->[0]; }
  my @b = ($l =~ /\*\*[^*]+\*\*/g); $bold += @b;
  my @e = ($l =~ /[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]/g); $emoji += @e;
  $h2++ if $l =~ /^##\s/;
  for my $t (@tone) { $aside++ if index($l, $t) >= 0; }
}
warn_(0, "太字が $bold か所ある。判断の芯 1 か所に絞る") if $bold > 2;
warn_(0, "絵文字が $emoji 個ある。意味のあるものを少しだけ") if $emoji > 3;
warn_(0, "本文 $body_lines 行に ## 見出しが $h2 個。箇条書きで足りないか") if $h2 >= 4 && $body_lines < 20;
warn_(0, "本音の一言が $aside か所ある。1 本文に 1 か所まで") if $aside > 1;
print "---\n$errors error(s), $warns warning(s)\n";
exit($errors ? 1 : 0);
' "$1"
