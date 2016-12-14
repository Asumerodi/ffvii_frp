#! /bin/bash
shopt -s extglob

main() {
  ########## global vars ##########


  # make temp working dir #
  mktemp -d /tmp/resize.XXXXXXXXXXXX > /dev/null
  tmpdir="$(find /tmp -mindepth 1 -prune -type d -name 'resize.*')"

  # set defualt output dir #
  mkdir -p "$HOME/FFVII_FRP"
  outdir="$HOME/FFVII_FRP"

  # set default input dir #
  indir="$HOME/FFVII_fields"

  # an array of scene dirs in $indir #
  scenes=("$(ls "$indir")")

  # the composite of working layers #
  composite="$tmpdir/composite.png"


  ########## main loop ##########


  # set trap for clean exit #
  trap finish EXIT

  cd "$indir" || exit

  for scene in ${scenes[@]}
    do
      # make scene dir #
      outscene="$outdir/$scene"
      mkdir -p "$outscene"

      cd "$scene" || exit

      # capture size of base image #
      size=$(identify "$(ls -- *000.png)" | awk '{print $3}')

      # arrays for main layers and auxilary layers #
      mLays=($(ls -- *_000001*.png *000.png))
      aLays=($(ls !(*_000001*|*_000[6-9]*|*000.)png 2&> /dev/null ))

      # process main layers #
      mainLay "${mLays[@]}"

      # if there are any aux layers handle them #
      if [[ -n "${aLays[@]}" ]]; then
        auxLay
      fi

      cd ..
    done
}

# $PHOTOMOD is waifu2x model dir held in an env var#
function scale {
  waifu2x-converter-cpp \
    --scale_ratio 4 \
    --model_dir \
    "$PHOTOMOD" \
    -m scale \
    -i "$composite" \
    -o "$composite"
}


# produces the main layers #
function mainLay {
  files=("$@")

  convert -size "$size" xc:black "$composite"

  # compose layers into single image #
  for file in ${files[@]}
    do
      composite "$file" "$composite" "$composite"
    done

  # scale and put base layer in output dir #
  scale
  cp "$composite" "$outscene/${files[0]}"

  # process remaining main layers from base #
  cutLayer "${files[@]}"
  noOverlap "${files[@]}"
}

# handle the auxilary layers one at a time #
function auxLay {
  for aLay in ${aLays[@]}
    do
      rm "$tmpdir/*"
      convert -size "$size" xc:black "$composite"

      # compose all main layers... #
      for mLay in ${mLays[@]}
        do
          composite "$mLay" "$composite" "$composite"
        done

      # with one aux layer #
      composite "$aLay" "$composite" "$composite"

      # scale the result #
      scale

      # first value is junk so that cutLayer loop will occur once #
      cutLayer "junk" "$aLay"

      # send only three values to avoid duplicate processing #
      noOverlap "${mLays[@]:(-2)}" "$aLay"
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

      # fill opacity with white; transparency with black... #
      convert "$file" \
        -fuzz 100% \
        -fill white \
        -opaque green \
        -background black \
        -alpha remove \
        "$pbm"

      # produce vector trace... #
      potrace -a 0 -b gimppath -x 3.2 \
        "$pbm" > "$svg"

      # rasterize and remove semi-transparent pixels... #
      convert -background none \
        "$svg" \
        -channel A \
        -threshold 1% \
        "$mask"

      # subtract from base image and place in outdir #
      convert "$composite" "$mask" \
        -gravity center \
        -compose CopyOpacity \
        -composite -channel A \
        -negate "$outscene/$file"
    done
}

# ensure layers do not share pixels #
function noOverlap {
  files=("$@")

  cd "$outscene" || exit

  # ensure the base image is not processed #
  for (( i=${#files[@]}-1; i > 1; i-- ))
    do
      # return first input image minus shared pixels #
      convert "${files[$i]}" "${files[$i-1]}" \
        -compose Change-mask \
        -composite "${files[$i]}"
    done

  cd - || exit
}

# cleanup temp dir #
function finish {
  rm -rf "$tmpdir"
}

main
