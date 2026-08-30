PKG_OPTIONS_VAR=        PKG_OPTIONS.compat_linux_test_project
PKG_SUPPORTED_OPTIONS=  static
PKG_SUGGESTED_OPTIONS=

.include "../../mk/bsd.options.mk"

.if !empty(PKG_OPTIONS:Mstatic)
LINK_MODE=      static
.else
LINK_MODE=      dynamic
EMUL_MODULES.linux=     base
.endif
