#!/bin/bash

# Etapa 13 - Instala o Android SDK (cmdline-tools, plataformas, build-tools,
# NDK, cmake, emulador) em ~/Android/Sdk
#
# O sdkmanager mudou o formato dos nomes dos pacotes: versões antigas usam
# "platforms;android-35" e as novas usam "platforms/android-35". O parsing
# abaixo normaliza para "/" e converte de volta para o separador detectado.

step_13_android_sdk() {
    ANDROID_HOME="$USER_HOME/Android/Sdk"
    ANDROID_JAVA_HOME="/opt/android-studio/jbr"
    SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
    show_message "Instalando Android SDK em $ANDROID_HOME"

    # O recover roda como root; ~/Android precisa pertencer ao usuário e ser
    # traversável por ele, senão o sdkmanager (executado via sudo -u) falha
    # com "Permissão negada".
    mkdir -p "$USER_HOME/Android" "$ANDROID_HOME"
    chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/Android"
    chmod 755 "$USER_HOME/Android"

    mkdir -p /tmp/cmdline-tools-extract
    LATEST_CMDLINE=$(curl -s "https://dl.google.com/android/repository/repository2-3.xml" \
        | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | sort -u -t- -k3 -n | tail -1 || true)
    [ -n "$LATEST_CMDLINE" ] || { echo "❌ Falha ao obter o cmdline-tools do Android"; return 1; }
    wget "https://dl.google.com/android/repository/$LATEST_CMDLINE" -O /tmp/cmdline-tools.zip
    unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv /tmp/cmdline-tools-extract/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
    chown -R "$USER_NAME:$USER_NAME" "$ANDROID_HOME"
    chmod -R a+rX "$ANDROID_HOME"

    user_do "export JAVA_HOME=$ANDROID_JAVA_HOME && yes | $SDKMANAGER --licenses >/dev/null 2>&1" || true

    show_message "Resolvendo pacotes do Android SDK (pode demorar)"
    if ! SDK_LIST=$(user_do "export JAVA_HOME=$ANDROID_JAVA_HOME && $SDKMANAGER --list"); then
        echo "❌ Falha ao executar o sdkmanager. Verifique $ANDROID_JAVA_HOME e as permissões de $ANDROID_HOME."
        return 1
    fi

    # Normaliza os caminhos para "/" (formato novo). O separador antigo ";"
    # é convertido de volta na hora de instalar.
    SDK_PATHS=$(printf '%s\n' "$SDK_LIST" | awk '/^  [a-zA-Z0-9]/ {print $1}' | tr ';' '/')
    SEP=";"
    printf '%s\n' "$SDK_LIST" | grep -q '^  platforms/android-' && SEP="/"

    PLATFORMS=$(printf '%s\n' "$SDK_PATHS" \
        | grep -E '^platforms/android-[0-9]+$' \
        | sed 's|platforms/android-||' | sort -n | tail -2)
    [ -n "$PLATFORMS" ] || { echo "❌ Nenhuma plataforma Android encontrada no SDK."; return 1; }

    SDK_PACKAGES=()
    local p pkg bt ndk cmake
    for p in $PLATFORMS; do
        SDK_PACKAGES+=("platforms/android-$p")
        printf '%s\n' "$SDK_PATHS" | grep -qx "sources/android-$p" \
            && SDK_PACKAGES+=("sources/android-$p")
        bt=$(printf '%s\n' "$SDK_PATHS" | grep -E "^build-tools/$p\.[0-9.]+$" | sort -V | tail -1)
        [ -n "$bt" ] && SDK_PACKAGES+=("$bt")
    done

    ndk=$(printf '%s\n' "$SDK_PATHS" | grep -E '^ndk/[0-9][0-9.]*$' | sort -V | tail -1)
    cmake=$(printf '%s\n' "$SDK_PATHS" | grep -E '^cmake/[0-9][0-9.]*$' | sort -V | tail -1)
    [ -n "$ndk" ] && SDK_PACKAGES+=("$ndk")
    [ -n "$cmake" ] && SDK_PACKAGES+=("$cmake")

    # Componentes avulsos: só adiciona os que existem nesta versão do SDK.
    for pkg in platform-tools emulator \
        extras/android/m2repository \
        extras/google/m2repository \
        extras/google/google_play_services \
        extras/google/market_apk_expansion \
        extras/google/market_licensing \
        extras/google/webdriver \
        skiaparser/1 skiaparser/2 skiaparser/3 \
        build/lightbuild/0.0.30; do
        printf '%s\n' "$SDK_PATHS" | grep -qx "$pkg" && SDK_PACKAGES+=("$pkg")
    done

    # Converte para o separador aceito pela versão do sdkmanager instalada.
    SDK_INSTALL=()
    for pkg in "${SDK_PACKAGES[@]}"; do
        SDK_INSTALL+=("${pkg//\//$SEP}")
    done
    SDK_PACKAGES_Q=$(printf '%q ' "${SDK_INSTALL[@]}")
    if ! user_do "export JAVA_HOME=$ANDROID_JAVA_HOME && yes | $SDKMANAGER $SDK_PACKAGES_Q"; then
        echo "❌ Falha ao instalar os pacotes do Android SDK."
        return 1
    fi

    if [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
        ln -sf "$ANDROID_HOME/platform-tools/adb" /usr/local/bin/adb
        show_message "adb disponível em /usr/local/bin/adb"
    else
        echo "❌ adb não encontrado em $ANDROID_HOME/platform-tools/adb"
        return 1
    fi

    # Evita duplicar as linhas a cada nova execução.
    grep -q '^ANDROID_HOME=' /etc/environment || echo "ANDROID_HOME=$ANDROID_HOME" >> /etc/environment
    grep -q '^ANDROID_SDK_ROOT=' /etc/environment || echo "ANDROID_SDK_ROOT=$ANDROID_HOME" >> /etc/environment
}
