# $NetBSD$

DISTINFO=	compat_linux_test_project-0.10
CATEGORIES=	emulators
MASTER_SITES=	# empty
DISTFILES=	# empty

MAINTAINER=	pkg-users@NetBSD.org
COMMENT=	Package to run the Linux Test Project tests on NetBSD

NO_CONFIGURE=	YES
NO_BUILD=		YES

ONLY_FOR_PLATFORM=	NetBSD-*-x86_64

USE_TOOLS+=	gmake pkgconf curl

DEPENDS+=	e2fsprogs-[0-9]*:../../sysutils/e2fsprogs
DEPENDS+=	suse_gcc12>=15.5:../../emulators/suse15_gcc12
DEPENDS+=	suse_binutils>=15.5:../../emulators/suse15_binutils
DEPENDS+=	suse_base>=15.5:../../emulators/suse15_base

BUILD_DEFS+=		VARBASE
INSTALLATION_DIRS=	bin
MAKE_DIRS+=			${VARBASE}/db/compat_linux_test_project

do-install:
	${INSTALL_SCRIPT} ${FILESDIR}/compat_linux_test_project.sh ${DESTDIR}${PREFIX}/bin/compat_linux_test_project

.include "../../mk/bsd.pkg.mk"
