#!/bin/bash
#
# Setup the build environment. This is based on the AppVeyor build script.
#

set -eax

# run 'where bash' and if it returns 'C:\Program Files\Git' then we set the build environment to 'msbuild' and Windows. We
# extract only the first line of the output of 'where bash' and compare it to 'C:\Program Files\Git\usr\bin\bash.exe'
if [ "$(where bash | head -n 1)" == "C:\Program Files\Git\usr\bin\bash.exe" ]; then
    BUILD_ENVIRONMENT="msbuild"
    TARGET="${TARGET:-vs2022}"
elif [ "$(uname -s)" == "Linux" ]; then
    BUILD_ENVIRONMENT=${BUILD_ENVIRONMENT:-python-tox}
elif [ "$(uname -s)" == "Darwin" ]; then
    BUILD_ENVIRONMENT=${BUILD_ENVIRONMENT:-xcode}
elif [[ "$(uname -s)" == CYGWIN_NT-10.0* ]]; then
    BUILD_ENVIRONMENT=${BUILD_ENVIRONMENT:-cygwin64}
elif [[ "$(uname -s)" == MINGW64_NT-10.0* ]]; then
    BUILD_ENVIRONMENT=${BUILD_ENVIRONMENT:-mingw-w64}
fi

PLATFORM=${PLATFORM:-x64}
CONFIGURATION=${CONFIGURATION:-Release}

if command -v brew &>/dev/null; then
    brew update-reset && brew update -q
    brew install -q autoconf automake gettext gnu-sed libtool pkg-config || true
elif command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get -y install \
        autoconf automake autopoint build-essential \
        flex git libtool patchelf pkg-config \
        python3 python3-dev python3-distutils python3-pip python3-setuptools tox twine
elif [ "$BUILD_ENVIRONMENT" == "cygwin64" ]; then
    wget https://cygwin.com/setup-x86_64.exe -O /cygwin64/setup-x86_64.exe
    /cygwin64/setup-x86_64.exe -qgnNdO -l /cygwin64/var/cache/setup -R /cygwin64 -s http://cygwin.mirror.constant.com -P gettext-devel -P python3-devel -P wget -P zlib-devel
elif [ "$BUILD_ENVIRONMENT" == "mingw-w64" ]; then
    pacman -S --noconfirm --needed \
        autoconf automake gettext-devel libtool make \
        mingw-w64-x86_64-gcc mingw-w64-x86_64-python3 \
        msys/zlib-devel
fi

if [ ! -e ../vstools ]; then
    git clone https://github.com/libyal/vstools.git ../vstools
fi

if [[ "cygwin64-gcc-no-optimization mingw-w64-gcc-no-optimization" =~ $TARGET ]]; then
    curl -o ../codecov.exe https://uploader.codecov.io/latest/windows/codecov.exe
fi

if command -v pwsh &>/dev/null && [ -f "./synctestdata.ps1" ]; then
    pwsh ./synctestdata.ps1
elif [ -f "./synctestdata.sh" ]; then
    ./synctestdata.sh
fi

if command -v pwsh &>/dev/null && [ -f "./synczlib.ps1" ]; then
    pwsh ./synczlib.ps1
fi

if command -v pwsh &>/dev/null; then
    pwsh ./synclibs.ps1
    pwsh ./autogen.ps1

    if [ "$TARGET" == "vs2008" ]; then
        pwsh ./build.ps1 -VisualStudioVersion 2008 -PythonPath "$PYTHON_PATH" -VSToolsOptions "--no-python-dll"
    elif [[ "vs2010 vs2012 vs2013 vs2015" =~ $TARGET ]]; then
        pwsh ./build.ps1 -VisualStudioVersion "${TARGET:2:4}" \
            -Configuration "$CONFIGURATION" -Platform "$PLATFORM" \
            -PythonPath "$PYTHON_PATH" -VSToolsOptions "--extend-with-x64 --no-python-dll"
    elif [[ "vs2017 vs2019 vs2022 vs2022-vsdebug vs2022-x64" =~ $TARGET ]]; then
        pwsh ./build.ps1 -VisualStudioVersion "${TARGET:2:4}" \
            -Configuration "$CONFIGURATION" -Platform "$PLATFORM" \
            -PythonPath "$PYTHON_PATH" -VSToolsOptions "--extend-with-x64 --no-python-dll --with-dokany"
    elif [ "$TARGET" == "vs2022-python" ]; then
        pwsh ./build.ps1 -VisualStudioVersion "${TARGET:2:4}" -Configuration "$CONFIGURATION" -Platform "$PLATFORM" -PythonPath "$PYTHON_PATH" -VSToolsOptions "--extend-with-x64 --python-path $PYTHON_PATH --with-dokany"
    fi
else
    ./synclibs.sh
    ./autogen.sh
    ./configure --disable-nls --disable-shared-libs
    make sources >/dev/null
fi

if [ -e /usr/local/opt/gettext/bin ]; then
    export PATH="/usr/local/opt/gettext/bin:$PATH"
fi

if [ -e /usr/local/bin/gsed ]; then
    export SED="/usr/local/bin/gsed"
fi

if [ "$BUILD_ENVIRONMENT" == "xcode" ]; then
    tests/build.sh "$CONFIGURE_OPTIONS"
fi

if [ -n "${TOXENV:-}" ]; then
    uv run tox -e"$TOXENV"
else
    uv run tox
fi

uv run tox -eauditwheel -- --plat "$AUDITWHEEL_PLAT" dist/*.whl
rm -f dist/*.whl
mv wheelhouse/*.whl dist/

if [ "$BUILD_ENVIRONMENT" == "cygwin64" ]; then
    bash -e -l -c "cd libpff && wget -q 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD' -O './config.guess' && wget -q 'http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD' -O './config.sub'"
    bash -e -l -c "cd libpff && tests/build.sh $CONFIGURE_OPTIONS"
fi

if [ "$BUILD_ENVIRONMENT" == "mingw-w64" ]; then
    bash -e -l -c "cd libpff && tests/build.sh $CONFIGURE_OPTIONS"
fi
