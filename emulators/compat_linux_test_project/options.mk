PKG_OPTIONS_VAR=                PKG_OPTIONS.compat_linux_test_project
PKG_OPTIONS_REQUIRED_GROUPS=	link-mode
PKG_OPTIONS_GROUP.link-mode=	static dynamic
PKG_SUGGESTED_OPTIONS=			dynamic

.include "../../mk/bsd.options.mk"

.if !empty(PKG_OPTIONS:Mstatic)
LINK_MODE=	static
.elif !empty(PKG_OPTIONS:Mdynamic)
LINK_MODE=	dynamic
EMUL_MODULES.linux=	base
.endif
