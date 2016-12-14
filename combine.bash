#! /bin/bash
shopt -s extglob

main() {
  # make temp working dir
  mktemp -d /tmp/resize.XXXXXXXXXXXX > /dev/null

  # global vars
  tmpdir="$(cd /tmp/resize.*;pwd)"
  size=$(identify $(ls *000.png) | awk '{print $3}')
  mainFiles=($(ls *_000001*.png *000.png))
  auxFiles=($(ls !(*_000001*|*_000[1-9]*|*000.)png))
  composite="$tmpdir/composite.png"

  # set trap for clean exit
  trap finish EXIT

  # main logic
  fstRun "${mainFiles[@]}"
  cutLayer "${mainFiles[@]}"
  noOverlap "${mainFiles[@]}"
  if [[ -n "$auxFiles" ]]; then
    secRun
  fi

}

function scale {
  waifu2x-converter-cpp \
    --scale_ratio 4 \
    --model_dir \
    $PHOTOMOD \
    -m scale \
    -i $composite \
    -o $composite
}


function fstRun {
  files=("$@")

  mkdir -p ./finished

  convert -size "$size" xc:black $composite

  for (( i=0; i < ${#files[@]}; i++ ))
    do
      composite ${files[$i]} $composite $composite
    done

  scale

  cp $composite finished/${files[0]}
}

function cutLayer {
  files=("$@")

  for (( i=1; i < ${#files[@]}; i++ ))
    do
      file=${files[$i]}
      pbm="$tmpdir/${files[$i]%%png}pbm"
      svg="$tmpdir/${files[$i]%%png}svg"
      mask="$tmpdir/${files[$i]%%.png}_mask.png"

      convert $file \
        -fuzz 100% \
        -fill white \
        -opaque green \
        -background black \
        -alpha remove \
        $pbm

      potrace -a 0 -b gimppath -x 3.2 \
        $pbm > $svg

      convert -background none \
        $svg \
        -channel A \
        -threshold 1% \
        $mask

      convert $composite $mask \
        -gravity center \
        -compose CopyOpacity \
        -composite -channel A \
        -negate finished/$file
    done
}

function noOverlap {
  files=("$@")

  cd finished

  for (( i=${#files[@]}-1; i > 1; i-- ))
    do
      convert ${files[$i]} ${files[$i-1]} \
        -compose Change-mask \
        -composite ${files[$i]}
    done

  cd ..
}

function secRun {
  for (( k=0; k < ${#auxFiles[@]}; k++))
    do
      rm $tmpdir/*
      convert -size "$size" xc:black $composite

      for (( j=0; j < ${#mainFiles[@]}; j++))
        do
          composite ${mainFiles[$j]} $composite $composite
        done

      composite ${auxFiles[$k]} $composite $composite

      scale

      # first value is junk so that cutLayer loop will occur once
      cutLayer "junk" "${auxFiles[$k]}"

      # send only three values to noOverlap
      noOverlap "${mainFiles[@]:(-2)}" "${auxFiles[$k]}"
    done
}

function finish {
  rm -rf $tmpdir
}

main
