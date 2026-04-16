TERMUX_PKG_HOMEPAGE="https://github.com/redrum/claude-voice-integration"
TERMUX_PKG_DESCRIPTION="Voice-triggered Claude CLI relay for Termux (Google Assistant → Claude)"
TERMUX_PKG_LICENSE="GPL-3.0"
TERMUX_PKG_MAINTAINER="@redrum"
TERMUX_PKG_VERSION="1.0.0"
TERMUX_PKG_SRCURL="https://github.com/redrum/claude-voice-integration/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256="skip"   # Update with real sha256 after publishing release tarball
TERMUX_PKG_DEPENDS="curl"
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_BUILD_IN_SRC=true

termux_step_make() {
    # Nothing to compile — pure shell package
    :
}

termux_step_make_install() {
    # Install main executable
    install -Dm 755 \
        "$TERMUX_PKG_SRCDIR/packages/claude-voice/files/usr/bin/claude-voice" \
        "$TERMUX_PREFIX/bin/claude-voice"

    # Install default config (only if not already present — preserve user edits)
    if [ ! -f "$TERMUX_PREFIX/etc/claude-voice.conf" ]; then
        install -Dm 644 \
            "$TERMUX_PKG_SRCDIR/packages/claude-voice/files/usr/etc/claude-voice.conf" \
            "$TERMUX_PREFIX/etc/claude-voice.conf"
    fi
}
