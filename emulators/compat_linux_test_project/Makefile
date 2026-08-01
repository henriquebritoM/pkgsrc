# $NetBSD$

CATEGORIES=	emulators

LTP_VERSION=	20260529
PKGNAME=	compat_linux_test_project-${LTP_VERSION}-0.10

MASTER_SITES=	https://github.com/linux-test-project/ltp/releases/download/${LTP_VERSION}/
DISTFILES=	ltp-full-${LTP_VERSION}.tar.xz

WRKSRC=		${WRKDIR}/ltp-full-${LTP_VERSION}

MAINTAINER=	pkg-users@NetBSD.org
COMMENT=	Package to build and run the Linux Test Project tests on NetBSD

NO_CONFIGURE=	YES

ONLY_FOR_PLATFORM=	NetBSD-*-x86_64

USE_TOOLS+=	gmake pkg-config

BUILD_DEPENDS+=	suse_gcc12>=15.5:../../emulators/suse15_gcc12
DEPENDS+=		e2fsprogs-[0-9]*:../../sysutils/e2fsprogs

LTP_PREFIX=	libexec/compat_linux_test_project

INSTALLATION_DIRS=	bin ${LTP_PREFIX}

GENERATE_PLIST+=	cd ${DESTDIR}${PREFIX}/${LTP_PREFIX} && \
			find . -type f | sed 's|^\./|${LTP_PREFIX}/|' ;

.include "options.mk"

do-build:
	cd ${WRKSRC} && ${SH} ${FILESDIR}/compile.sh --ltp-version ${LTP_VERSION} \
		--dest ${WRKSRC}/${LTP_PREFIX} --link-mode "${LINK_MODE}"

do-install:
	${INSTALL_SCRIPT} ${FILESDIR}/compat_tester.sh \
		${DESTDIR}${PREFIX}/bin/compat_linux_test_project
	cd ${WRKSRC}/${LTP_PREFIX} && \
		pax -rw . ${DESTDIR}${PREFIX}/${LTP_PREFIX}

.include "../../mk/bsd.pkg.mk"
