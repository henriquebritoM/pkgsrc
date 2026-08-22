# $NetBSD$
LTP_VERSION=    20260529

PKGNAME=        compat_linux_test_project-${LTP_VERSION}-0.10
CATEGORIES=     emulators
MASTER_SITES=   ${MASTER_SITE_GITHUB:=linux-test-project/}ltp/releases/download/${LTP_VERSION}/
DISTFILES=      ltp-full-${LTP_VERSION}.tar.xz

WRKSRC=         ${WRKDIR}/ltp-full-${LTP_VERSION}

MAINTAINER=     pkg-users@NetBSD.org
COMMENT=        Package to build and run the Linux Test Project tests on NetBSD
LICENSE=        2-clause-bsd

NO_CONFIGURE=   YES

USE_TOOLS+=     gmake pax

BUILD_DEPENDS+= suse_gcc12>=15.5:../../emulators/suse15_gcc12
DEPENDS+=       e2fsprogs-[0-9]*:../../sysutils/e2fsprogs

EMUL_PLATFORMS=         linux-x86_64
EMUL_REQD+=             suse>=15.5

LTP_PREFIX=     libexec/compat_linux_test_project

EGDIR=                  ${PREFIX}/share/examples/compat_linux_test_project
INSTALLATION_DIRS=      bin ${LTP_PREFIX} share/examples/compat_linux_test_project

GENERATE_PLIST+=        cd ${DESTDIR}${PREFIX}/${LTP_PREFIX} && \
                        find . -type f | sed 's|^\./|${LTP_PREFIX}/|' ;

do-build:
		cd ${WRKSRC} && ${SH} ${FILESDIR}/compile.sh --ltp-version ${LTP_VERSION} \
			--dest ${WRKSRC}/${LTP_PREFIX} --link-mode "${LINK_MODE}"
		${INSTALL_DATA} ${FILESDIR}/linux_config ${WRKSRC}/${LTP_PREFIX}/linux_config
		mkdir -p ${WRKSRC}/${LTP_PREFIX}/reference_logs/reference
		cd ${FILESDIR}/reference_logs/NetBSD11-reference && \
			pax -rw . ${WRKSRC}/${LTP_PREFIX}/reference_logs/reference

do-install:
		${INSTALL_SCRIPT} ${FILESDIR}/compat_tester.sh \
        		${DESTDIR}${PREFIX}/bin/compat_linux_test_project
		cd ${WRKSRC}/${LTP_PREFIX} && \
        		pax -rw . ${DESTDIR}${PREFIX}/${LTP_PREFIX}

post-install:
		${INSTALL_DATA} ${FILESDIR}/examples/*.txt ${DESTDIR}${EGDIR}/

.include "options.mk"
.include "../../mk/bsd.pkg.mk"
