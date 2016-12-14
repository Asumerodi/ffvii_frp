#! /bin/bash
shopt -s extglob

main() {
  ########## global vars ##########


  # make temp working dir #
  mktemp -d /tmp/resize.XXXXXXXXXXXX > /dev/null
  tmpdir="$(cd /tmp/resize.*;pwd)"

  # set defualt output dir #
  mkdir -p $HOME/FFVII_FRP
  outdir="$HOME/FFVII_FRP"

  # capture size of base image #
  size=$(identify $(ls *000.png) | awk '{print $3}')

  # arrays for main layers and auxilary layers #
  mainLays=($(ls *_000001*.png *000.png))
  auxLays=($(ls !(*_000001*|*_000[1-9]*|*000.)png))

  # the composite of working layers #
  composite="$tmpdir/composite.png"


  ########## main logic ##########


  # set trap for clean exit #
  trap finish EXIT

  # process main layers #
  mainLay "${mainLays[@]}"

  # if there are any aux layers handle them #
  if [[ -n "$auxLays" ]]; then
    auxLay
  fi
}

# $PHOTOMOD is waifu2x model dir #
function scale {
  waifu2x-converter-cpp \
    --scale_ratio 4 \
    --model_dir \
    $PHOTOMOD \
    -m scale \
    -i $composite \
    -o $composite
}


# produces the main layers #
function mainLay {
  files=("$@")

  convert -size "$size" xc:black $composite

  # compose layers into single image #
  for (( i=0; i < ${#files[@]}; i++ ))
    do
      composite ${files[$i]} $composite $composite
    done

  # scale and put base layer in output dir #
  scale
  cp $composite $outdir/${files[0]}

  # process remaining main layers from base #
  cutLayer "${files[@]}"
  noOverlap "${files[@]}"
}

# handle the auxilary layers one at a time #
function auxLay {
  for (( k=0; k < ${#auxLays[@]}; k++))
    do
      rm $tmpdir/*
      convert -size "$size" xc:black $composite

      # compose all main layers... #
      for (( j=0; j < ${#mainLays[@]}; j++))
        do
          composite ${mainLays[$j]} $composite $composite
        done

      # with one aux layer #
      composite ${auxLays[$k]} $composite $composite

      # scale the result #
      scale

      # first value is junk so that cutLayer loop will occur once #
      cutLayer "junk" "${auxLays[$k]}"

      # send only three values to avoid duplicate processing #
      noOverlap "${mainLays[@]:(-2)}" "${auxLays[$k]}"
    done
}

# produce the enlarged layers #
function cutLayer {
  files=("$@")

  for (( i=1; i < ${#files[@]}; i++ ))
    do
      # vars for current and temp files #
      file=${files[$i]}
      pbm="$tmpdir/${files[$i]%%png}pbm"
      svg="$tmpdir/${files[$i]%%png}svg"
      mask="$tmpdir/${files[$i]%%.png}_mask.png"

      # convert original layer to black and white... #
      convert $file \
        -fuzz 100% \
        -fill white \
        -opaque green \
        -background black \
        -alpha remove \
        $pbm

      # produce upscaled vector trace... #
      potrace -a 0 -b gimppath -x 3.2 \
        $pbm > $svg

      # rasterize and remove semi transparent pixels... #
      convert -background none \
        $svg \
        -channel A \
        -threshold 1% \
        $mask

      # subtract from base image and place in outdir #
      convert $composite $mask \
        -gravity center \
        -compose CopyOpacity \
        -composite -channel A \
        -negate $outdir/$file
    done
}

# ensure layers do not share pixels #
function noOverlap {
  files=("$@")

  cd $outdir

  # ensure the base image is not processed #
  for (( i=${#files[@]}-1; i > 1; i-- ))
    do
      # return input image minus share pixels #
      convert ${files[$i]} ${files[$i-1]} \
        -compose Change-mask \
        -composite ${files[$i]}
    done

  cd -
}

# cleanup temp dir #
function finish {
  rm -rf $tmpdir
}

main
