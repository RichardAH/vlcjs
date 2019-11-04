#! /bin/sh
set -e

## FUNCTIONS

diagnostic()
{
     echo "$@" 1>&2;
}

checkfail()
{
    if [ ! $? -eq 0 ];then
        diagnostic "$1"
        exit 1
    fi
}


# Download the portable SDK and uncompress it
if [ ! -d emsdk ]; then
    diagnostic "emsdk not found. Fetching it"
    git clone http://github.com/emscripten-core/emsdk.git emsdk
    cd emsdk && ./emsdk update-tags && ./emsdk install tot-upstream && ./emsdk activate tot-upstream
    checkfail "emsdk: fetch failed"
fi


# Go go go vlc
if [ ! -d "vlc" ]; then
    diagnostic "VLC source not found, cloning"
    git clone http://git.videolan.org/git/vlc.git vlc
    checkfail "vlc source: git clone failed"
fi

cd vlc

# Make in //
if [ -z "$MAKEFLAGS" ]; then
    UNAMES=$(uname -s)
    MAKEFLAGS=
    if which nproc >/dev/null; then
        MAKEFLAGS=-j`nproc`
    elif [ "$UNAMES" == "Darwin" ] && which sysctl >/dev/null; then
        MAKEFLAGS=-j`sysctl -n machdep.cpu.thread_count`
    fi
fi

# VLC tools
export PATH=`pwd`/extras/tools/build/bin:$PATH
echo "Building tools"
cd extras/tools
./bootstrap
checkfail "buildsystem tools: bootstrap failed"
make $MAKEFLAGS
checkfail "buildsystem tools: make"
cd ../../..

diagnostic "Setting the environment"
source emsdk/emsdk_env.sh
export PKG_CONFIG_PATH=$EMSDK/emscripten/incoming/system/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$PWD/vlc/contrib/wasm32_unknowm_emscripten/lib/pkgconfig
export PKG_CONFIG_PATH_CUSTOM=$PKG_CONFIG_LIBDIR

# Check that clang is working
clang --version

diagnostic "Patching"

cd vlc

# patching vlc
if [ -d ../patch_vlc ] && [ "$(ls -A ../patch_vlc)" ]; then
    git am -3 ../patch_vlc/*
fi

# BOOTSTRAP

if [ ! -f configure ]; then
    echo "Bootstraping"
    ./bootstrap
    checkfail "vlc: bootstrap failed"
fi

############
# Contribs #
############

echo "Building the contribs"
mkdir -p contrib/contrib-emscripten
cd contrib/contrib-emscripten

    ../bootstrap --disable-disc --disable-gpl --disable-sout \
    --disable-network \
    --host=wasm32-unknown-emscripten --build=x86_64-linux
checkfail "contribs: bootstrap failed"

emmake make list
emmake make $MAKEFLAGS fetch
checkfail "contribs: make fetch failed"
emmake make $MAKEFLAGS .ffmpeg

checkfail "contribs: make failed"

cd ../../

# Build
mkdir -p build-emscripten && cd build-emscripten

OPTIONS="
    --host=asmjs-unknown-emscripten
    --enable-debug
    --enable-gles2
    --disable-nls
    --disable-sout
    --disable-vlm
    --disable-addonmanagermodules
    --disable-avcodec
    --enable-merge-ffmpeg
    --disable-swscale
    --disable-a52
    --disable-x264
    --disable-xcb
    --disable-xvideo
    --disable-alsa
    --disable-macosx
    --disable-sparkle
    --disable-qt
    --disable-screen
    --disable-xcb
    --disable-pulse
    --disable-alsa
    --disable-oss
    --disable-vlc"

# Note :
#        search.h is a blacklisted module
#        time.h is a blacklisted module
    ac_cv_func_sendmsg=yes ac_cv_func_recvmsg=yes ac_cv_func_if_nameindex=yes ac_cv_header_search_h=no ac_cv_header_time_h=no \
../configure ${OPTIONS}

make ${MAKEFLAGS}

diagnostic "Generating module list"
cd ../..
./generate_modules_list.sh
cd vlc/build-emscripten
emcc vlc-modules.c -o vlc-modules.bc
cd ../..

# copy Dolby_Canyon.vob
diagnostic "copying video"
cp Dolby_Canyon.vob vlc/build-emscripten/Dolby_Canyon.vob

diagnostic "Generating executable"
cp main.c vlc/build-emscripten/
./create_main.sh
