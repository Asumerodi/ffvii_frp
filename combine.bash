#! /bin/bash
set -eu -o pipefail
shopt -s extglob nullglob


main() {
  ########## global vars ##########


  # make temp working dir #
  tmpdir="$(mktemp -d /tmp/resize.XXXXXXXXXXXX)/"

  # set defualt output dir #
  outdir="$HOME/FFVII_FRP/"
  mkdir -p "$outdir"

  # set default input dir #
  indir="$HOME/FFVII_fields/"

  # an array of scene dirs in $indir #
  scenes=("$indir"*/)

  # the composite of working layers #
  composite="${tmpdir}composite.png"


  ########## main loop ##########


  # set trap for clean exit #
  trap finish EXIT

  for scene in "${scenes[@]}"
    do
      # get basename without calling basename #
      outscene="$outdir${scene#${scene%/*/}/}"
      mkdir -p "$outscene"

      cd "$scene"

      # capture size of base image #
      size=$(identify -format "%wx%h" -- *000.png)

      # arrays for main layers and auxilary layers #
      mLays=( @(*000001*|*000).png )
      echo "${mLays[@]}"
      aLays=( !(*_000001*|*_000[6-9]*|*000.)png )
      echo "${aLays[@]}"

      # process main layers #
      mainLay "${mLays[@]}"

      # if there are any aux layers handle them #
      if [[ -n "${aLays[@]}" ]]; then
        auxLay
      fi
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
    -o "$composite" > /dev/null
}


# produces the main layers #
function mainLay {
  files=("$@")

  convert -size "$size" xc:black "$composite"

  # compose layers into single image #
  for file in "${files[@]}"
    do
      composite "$file" "$composite" "$composite"
    done

  # scale and put base layer in output dir #
  scale
  cp "$composite" "$outscene${files[0]}"

  # process remaining main layers from base #
  cutLayer "${files[@]}"
  noOverlap "${files[@]}"
}

# handle the auxilary layers one at a time #
function auxLay {
  for aLay in "${aLays[@]}"
    do
      rm "$tmpdir"*
      convert -size "$size" xc:black "$composite"

      # compose all main layers... #
      for mLay in "${mLays[@]}"
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
      pbm="$tmpdir${files[$i]%%png}pbm"
      svg="$tmpdir${files[$i]%%png}svg"
      mask="$tmpdir${files[$i]%%.png}_mask.png"

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
        -negate "$outscene$file"
    done
}

# ensure layers do not share pixels #
function noOverlap {
  files=("$@")

  # ensure the base image is not processed #
  for (( i=${#files[@]}-1; i > 1; i-- ))
    do
      # return first input image minus shared pixels #
      convert "$outscene${files[$i]}" "$outscene${files[$i-1]}" \
        -compose Change-mask \
        -composite "$outscene${files[$i]}"
    done
}

# cleanup temp dir #
function finish {
  rm -r "$tmpdir"
}

main
