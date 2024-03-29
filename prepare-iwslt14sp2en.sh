#!/usr/bin/env bash
#
# Adapted from https://github.com/facebookresearch/MIXER/blob/master/prepareData.sh

echo 'Cloning Moses github repository (for tokenization scripts)...'
git clone https://github.com/moses-smt/mosesdecoder.git

echo 'Cloning Subword NMT repository (for BPE pre-processing)...'
git clone https://github.com/rsennrich/subword-nmt.git

SCRIPTS=mosesdecoder/scripts
TOKENIZER=$SCRIPTS/tokenizer/tokenizer.perl
LC=$SCRIPTS/tokenizer/lowercase.perl
CLEAN=$SCRIPTS/training/clean-corpus-n.perl
BPEROOT=subword-nmt/subword_nmt
BPE_TOKENS=25000

URL="https://wit3.fbk.eu/archive/2014-01/texts/es/en/es-en.tgz"
URL1="https://www.statmt.org/europarl/v6/es-en.tgz"
#URL2="https://s3.amazonaws.com/web-language-models/paracrawl/release5/en-es.bicleaner07.txt.gz"
URL3="https://stuncorpusprod.blob.core.windows.net/corpusfiles/UNv1.0.en-es.tar.gz.00"
URL4="https://stuncorpusprod.blob.core.windows.net/corpusfiles/UNv1.0.en-es.tar.gz.01"
GZ=es-en.tgz
GZ2=en-es.bicleaner07.txt.gz

if [ ! -d "$SCRIPTS" ]; then
    echo "Please set SCRIPTS variable correctly to point to Moses scripts."
    exit
fi

src=es
tgt=en
lang=es-en
prep=iwslt14.tokenized.es-en
tmp=$prep/tmp
orig=orig

mkdir -p $orig $tmp $prep

echo "Downloading data from ${URL}..."
cd $orig
wget "$URL"


if [ -f $GZ ]; then
    echo "Data successfully downloaded."
else
    echo "Data not successfully downloaded."
    exit
fi

tar zxvf $GZ
cd $lang
wget "$URL1"
tar zxvf $GZ
#wget "$URL2"
#gzip -d $GZ2
#cut -f1 en-es.bicleaner07.txt > big-text.en
#cut -f2 en-es.bicleaner07.txt > big-text.es
wget "$URL3"
wget "$URL4"
cat UNv1.0.en-es.tar.gz.* >UNv1.0.en-es.tar.gz
tar -xzf UNv1.0.en-es.tar.gz


cd ..
cd ..

echo "pre-processing train data..."
for l in $src $tgt; do
    f=train.tags.$lang.$l
    tok=train.tags.$lang.tok.$l

    cat $orig/$lang/$f | \
    grep -v '<url>' | \
    grep -v '<talkid>' | \
    grep -v '<keywords>' | \
    sed -e 's/<title>//g' | \
    sed -e 's/<\/title>//g' | \
    sed -e 's/<description>//g' | \
    sed -e 's/<\/description>//g' > final.$l
    cat final.$l $orig/$lang/europarl-v6.es-en.$l '''$orig/$lang/big-text.$l''' $orig/$lang/en-es/UNv1.0.en-es.$l | \
    perl $TOKENIZER -threads 8 -l $l > $tmp/$tok
    echo ""
done
perl $CLEAN -ratio 1.5 $tmp/train.tags.$lang.tok $src $tgt $tmp/train.tags.$lang.clean 1 175
for l in $src $tgt; do
    perl $LC < $tmp/train.tags.$lang.clean.$l > $tmp/train.tags.$lang.$l
done

echo "pre-processing valid/test data..."
for l in $src $tgt; do
    for o in `ls $orig/$lang/IWSLT14.TED*.$l.xml`; do
    fname=${o##*/}
    f=$tmp/${fname%.*}
    echo $o $f
    grep '<seg id' $o | \
        sed -e 's/<seg id="[0-9]*">\s*//g' | \
        sed -e 's/\s*<\/seg>\s*//g' | \
        sed -e "s/\’/\'/g" | \
    perl $TOKENIZER -threads 8 -l $l | \
    perl $LC > $f
    echo ""
    done
done


echo "creating train, valid, test..."
for l in $src $tgt; do
    awk '{if (NR%23 == 0)  print $0; }' $tmp/train.tags.es-en.$l > $tmp/valid.$l
    awk '{if (NR%23 != 0)  print $0; }' $tmp/train.tags.es-en.$l > $tmp/train.$l

    cat $tmp/IWSLT14.TED.dev2010.es-en.$l \
        $tmp/IWSLT14.TEDX.dev2012.es-en.$l \
        $tmp/IWSLT14.TED.tst2010.es-en.$l \
        $tmp/IWSLT14.TED.tst2011.es-en.$l \
        $tmp/IWSLT14.TED.tst2012.es-en.$l \
        > $tmp/test.$l
done

TRAIN=$tmp/train.es-en
BPE_CODE=$prep/code
rm -f $TRAIN
for l in $src $tgt; do
    cat $tmp/train.$l >> $TRAIN
done

echo "learn_bpe.py on ${TRAIN}..."
python $BPEROOT/learn_bpe.py -s $BPE_TOKENS < $TRAIN > $BPE_CODE

for L in $src $tgt; do
    for f in train.$L valid.$L test.$L; do
        echo "apply_bpe.py to ${f}..."
        python $BPEROOT/apply_bpe.py -c $BPE_CODE < $tmp/$f > $prep/$f
    done
done
